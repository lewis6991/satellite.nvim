" WARN: Sometimes 1-indexing is used (primarily for mutual Vim/Neovim API
" calls) and sometimes 0-indexing (primarily for Neovim-specific API calls).
" WARN: Functionality that temporarily moves the cursor and restores it should
" use a window workspace to prevent unwanted side effects. More details are in
" the documentation for lua/scrollview.lua::open_win_workspace.

" *************************************************
" * Globals
" *************************************************

" Internal flag for tracking scrollview state.
let s:scrollview_enabled = get(s:, 'scrollview_enabled', 0)

let s:lua_module = luaeval('require("scrollview")')

" Since there is no text displayed in the buffers, the same buffers are used
" for multiple windows. This also prevents the buffer list from getting high
" from usage of the plugin.

" s:bar_bufnr has the bufnr of the buffer created for a position bar.
let s:bar_bufnr = get(s:, 'bar_bufnr', -1)

" s:overlay_bufnr has the bufnr of the buffer created for the click overlay.
let s:overlay_bufnr = get(s:, 'overlay_bufnr', -1)

" Keep count of pending async refreshes.
let s:pending_async_refresh_count = 0

" A window variable is set on each scrollview window, as a way to check for
" scrollview windows, in addition to matching the scrollview buffer number
" saved in s:bar_bufnr. This was preferable versus maintaining a list of
" window IDs.
let s:win_var = 'scrollview_key'
let s:win_val = 'scrollview_val'

" A key for saving scrollbar properties using a window variable.
let s:props_var = 'scrollview_props'

" A key for flagging windows that are pending async removal.
let s:pending_async_removal_var = 'scrollview_pending_async_removal'

" *************************************************
" * Utils
" *************************************************

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

function! s:NumberToFloat(number) abort
  return a:number + 0.0
endfunction

function! s:ReltimeToMicroseconds(reltime) abort
  let l:reltimestr = reltimestr(a:reltime)
  return str2nr(join(split(l:reltimestr, '\.'), ''))
endfunction

" *************************************************
" * Core
" *************************************************

function! s:IsVisualMode(mode) abort
  return s:Contains(['v', 'V', "\<c-v>"], a:mode)
endfunction

function! s:IsSelectMode(mode) abort
  return s:Contains(['s', 'S', "\<c-s>"], a:mode)
endfunction

" Returns true for ordinary windows (not floating and not external), and
" false otherwise.
function! s:IsOrdinaryWindow(winid) abort
  let l:config = nvim_win_get_config(a:winid)
  let l:not_external = !get(l:config, 'external', 0)
  let l:not_floating = get(l:config, 'relative', '') ==# ''
  return l:not_external && l:not_floating
endfunction

" Returns a list of window IDs for the ordinary windows.
function! s:GetOrdinaryWindows() abort
  let l:winids = []
  for l:winnr in range(1, winnr('$'))
    let l:winid = win_getid(l:winnr)
    if s:IsOrdinaryWindow(l:winid)
      call add(l:winids, l:winid)
    endif
  endfor
  return l:winids
endfunction

function! s:InCommandLineWindow() abort
  if win_gettype() ==# 'command' | return 1 | endif
  if mode() ==# 'c' | return 1 | endif
  let l:winnr = winnr()
  let l:bufnr = winbufnr(l:winnr)
  let l:buftype = nvim_buf_get_option(l:bufnr, 'buftype')
  let l:bufname = bufname(l:bufnr)
  return l:buftype ==# 'nofile' && l:bufname ==# '[Command Line]'
endfunction

" (documented in scrollview.lua)
function! s:OpenWinWorkspace(winid) abort
  return s:lua_module.open_win_workspace(a:winid)
endfunction

" Returns true if the window has at least one fold (either closed or open).
function! s:WindowHasFold(winid) abort
  " A window has at least one fold if 1) the first line is within a fold or 2)
  " it's possible to move from the first line to some other line with a fold.
  let l:winid = a:winid
  let l:init_winid = win_getid()
  let l:result = 0
  call win_gotoid(l:winid)
  if foldlevel(1) !=# 0
    let l:result = 1
  else
    let l:workspace_winid = s:OpenWinWorkspace(l:winid)
    call win_gotoid(l:workspace_winid)
    keepjumps normal! ggzj
    let l:result = line('.') !=# 1
    " Leave the workspace so it can be closed. Return to the existing window,
    " which was l:winid (from the win_gotoid call above).
    call win_gotoid(l:winid)
    call s:lua_module.close_window(l:workspace_winid)
  endif
  call win_gotoid(l:init_winid)
  return l:result
endfunction

" Returns the window column where the buffer's text begins. This may be
" negative due to horizontal scrolling. This may be greater than one due to
" the sign column and 'number' column.
function! s:BufferTextBeginsColumn(winid) abort
  let l:current_winid = win_getid(winnr())
  call win_gotoid(a:winid)
  " The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  let l:wrap = &l:wrap
  setlocal nowrap
  let l:result = wincol() - virtcol('.') + 1
  let &l:wrap = l:wrap
  call win_gotoid(l:current_winid)
  return l:result
endfunction

" Returns the window column where the view of the buffer begins. This can be
" greater than one due to the sign column and 'number' column.
function! s:BufferViewBeginsColumn(winid) abort
  let l:current_winid = win_getid(winnr())
  call win_gotoid(a:winid)
  " The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  let l:wrap = &l:wrap
  setlocal nowrap
  let l:result = wincol() - virtcol('.') + winsaveview().leftcol + 1
  let &l:wrap = l:wrap
  call win_gotoid(l:current_winid)
  return l:result
endfunction

" Returns the specified variable. There are two optional arguments, for
" specifying precedence and a default value. Without specifying precedence,
" highest precedence is given to window variables, then tab page variables,
" then buffer variables, then global variables. Without specifying a default
" value, 0 will be used.
function! s:GetVariable(name, winnr, ...) abort
  " WARN: The try block approach below is used instead of getwinvar(a:winnr,
  " a:name), since the latter approach provides no way to know whether a
  " returned default value was from a missing key or a match that
  " coincidentally had the same value.
  let l:precedence = 'wtbg'
  if a:0 ># 0
    let l:precedence = a:1
  endif
  for l:idx in range(strchars(l:precedence))
    let l:c = strcharpart(l:precedence, l:idx, 1)
    if l:c ==# 'w'
      let l:winvars = getwinvar(a:winnr, '')
      try | return l:winvars[a:name] | catch | endtry
    elseif l:c ==# 't'
      try | return t:[a:name] | catch | endtry
    elseif l:c ==# 'b'
      let l:bufnr = winbufnr(a:winnr)
      let l:bufvars = getbufvar(l:bufnr, '')
      try | return l:bufvars[a:name] | catch | endtry
    elseif l:c ==# 'g'
      try | return g:[a:name] | catch | endtry
    else
      throw 'Unknown variable type ' . l:c
    endif
  endfor
  let l:default = 0
  if a:0 ># 1
    let l:default = a:2
  endif
  return l:default
endfunction

" Returns the scrollview mode. The function signature matches s:GetVariable,
" without the 'name' argument.
function! s:ScrollViewMode(...) abort
  " When g:scrollview_refresh_time_exceeded was exceeded, always use 'simple'
  " mode.
  if g:scrollview_refresh_time_exceeded
    return 'simple'
  endif
  let l:args = ['scrollview_mode'] + a:000
  return call(function('s:GetVariable'), l:args)
endfunction

" (documented in scrollview.lua)
function! s:VirtualLineCount(winid, start, end) abort
  let l:result = s:lua_module.virtual_line_count(a:winid, a:start, a:end)
  " Lua only has floats. Convert to integer as a precaution.
  return float2nr(l:result)
endfunction

" Return top line and bottom line in window. For folds, the top line
" represents the start of the fold and the bottom line represents the end of
" the fold.
function! s:LineRange(winid) abort
  " WARN: getwininfo(winid)[0].botline is not properly updated for some
  " movements (Neovim Issue #13510), so this is implemeneted as a workaround.
  " This was originally handled by using an asynchronous context, but this was
  " not possible for refreshing bars during mouse drags.
  let l:current_winid = win_getid(winnr())
  call win_gotoid(a:winid)
  " Using scrolloff=0 combined with H and L breaks diff mode. Scrolling is not
  " possible and/or the window scrolls when it shouldn't. Temporarily turning
  " off scrollbind and cursorbind accommodates, but the following is simpler.
  let l:topline = line('w0')
  let l:botline = line('w$')
  " line('w$') returns 0 in silent Ex mode, but line('w0') is always greater
  " than or equal to 1.
  let l:botline = max([l:botline, l:topline])
  call win_gotoid(l:current_winid)
  return [l:topline, l:botline]
endfunction

" Calculates the bar position for the specified window. Returns a dictionary
" with a height, row, and col.
function! s:CalculatePosition(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
  let l:bufnr = winbufnr(l:winnr)
  let [l:topline, l:botline] = s:LineRange(l:winid)
  let l:line_count = nvim_buf_line_count(l:bufnr)
  let l:effective_topline = l:topline
  let l:effective_line_count = l:line_count
  let l:scrollview_mode = s:ScrollViewMode(l:winnr)
  if l:scrollview_mode !=# 'simple'
    " For virtual mode or an unknown mode, update effective_topline and
    " effective_line_count to correspond to virtual lines, which account for
    " closed folds.
    let l:effective_topline =
          \ s:VirtualLineCount(l:winid, 1, l:topline - 1) + 1
    let l:effective_line_count = s:VirtualLineCount(l:winid, 1, '$')
  endif
  let l:winheight = winheight(l:winnr)
  let l:winwidth = winwidth(l:winnr)
  " l:top is the position for the top of the scrollbar, relative to the
  " window, and 0-indexed.
  let l:top = 0
  if l:effective_line_count ># 1
    let l:top = (l:effective_topline - 1.0) / (l:effective_line_count - 1)
    let l:top = float2nr(round((l:winheight - 1) * l:top))
  endif
  let l:height = l:winheight
  if l:effective_line_count ># l:height
    let l:height = s:NumberToFloat(l:winheight) / l:effective_line_count
    let l:height = float2nr(ceil(l:height * l:winheight))
    let l:height = max([1, l:height])
  endif
  " Make sure bar properly reflects bottom of document.
  if l:botline ==# l:line_count
    let l:top = l:winheight - l:height
  endif
  " Make sure bar never overlaps status line.
  if l:top + l:height ># l:winheight
    let l:top = l:winheight - l:height
  endif
  " l:left is the position for the left of the scrollbar, relative to the
  " window, and 0-indexed.
  let l:left = 0
  let l:column = s:GetVariable('scrollview_column', l:winnr)
  let l:base = s:GetVariable('scrollview_base', l:winnr)
  if l:base ==# 'left'
    let l:left += l:column - 1
  elseif l:base ==# 'right'
    let l:left += l:winwidth - l:column
  elseif l:base ==# 'buffer'
    let l:left += l:column - 1
          \ + s:BufferTextBeginsColumn(l:winid) - 1
  else
    " For an unknown base, use the default position (right edge of window).
    let l:left += l:winwidth - 1
  endif
  let l:result = {
        \   'height': l:height,
        \   'row': l:top + 1,
        \   'col': l:left + 1
        \ }
  return l:result
endfunction

function! s:ShowScrollbar(winid) abort
  let l:winid = a:winid
  let l:winnr = win_id2win(l:winid)
  let l:bufnr = winbufnr(l:winnr)
  let l:buf_filetype = getbufvar(l:bufnr, '&l:filetype', '')
  let l:winheight = winheight(l:winnr)
  let l:winwidth = winwidth(l:winnr)
  " Skip if the filetype is on the list of exclusions.
  let l:excluded_filetypes =
        \ s:GetVariable('scrollview_excluded_filetypes', l:winnr)
  if s:Contains(l:excluded_filetypes, l:buf_filetype)
    return
  endif
  " Don't show in terminal mode, since the bar won't be properly updated for
  " insertions.
  if getwininfo(l:winid)[0].terminal
    return
  endif
  if l:winheight ==# 0 || l:winwidth ==# 0
    return
  endif
  let l:line_count = nvim_buf_line_count(l:bufnr)
  " Don't show the position bar when all lines are on screen.
  let [l:topline, l:botline] = s:LineRange(l:winid)
  if l:botline - l:topline + 1 ==# l:line_count
    return
  endif
  let l:bar_position = s:CalculatePosition(l:winnr)
  " Height has to be positive for the call to nvim_open_win. When opening a
  " terminal, the topline and botline can be set such that height is negative
  " when you're using scrollview document mode.
  if l:bar_position.height <=# 0
    return
  endif
  " Don't show scrollbar when its column is beyond what's valid.
  let l:min_valid_col = 1
  let l:max_valid_col = l:winwidth
  let l:base = s:GetVariable('scrollview_base', l:winnr)
  if l:base ==# 'buffer'
    let l:min_valid_col = s:BufferViewBeginsColumn(l:winid)
  endif
  if l:bar_position.col <# l:min_valid_col
    return
  endif
  if l:bar_position.col ># l:winwidth
    return
  endif
  if s:bar_bufnr ==# -1 || !bufexists(s:bar_bufnr)
    let s:bar_bufnr = nvim_create_buf(0, 1)
    call setbufvar(s:bar_bufnr, '&modifiable', 0)
    call setbufvar(s:bar_bufnr, '&filetype', 'scrollview')
    call setbufvar(s:bar_bufnr, '&buftype', 'nofile')
    call setbufvar(s:bar_bufnr, '&swapfile', 0)
    call setbufvar(s:bar_bufnr, '&bufhidden', 'hide')
    call setbufvar(s:bar_bufnr, '&buflisted', 0)
  endif
  let l:options = {
        \   'win': l:winid,
        \   'relative': 'win',
        \   'focusable': 0,
        \   'style': 'minimal',
        \   'height': l:bar_position.height,
        \   'width': 1,
        \   'row': l:bar_position.row - 1,
        \   'col': l:bar_position.col - 1
        \ }
  let l:bar_winid = nvim_open_win(s:bar_bufnr, 0, l:options)
  " It's not sufficient to just specify Normal highlighting. With just that, a
  " color scheme's specification of EndOfBuffer would be used to color the
  " bottom of the scrollbar.
  let l:bar_winnr = win_id2win(l:bar_winid)
  let l:winhighlight = 'Normal:ScrollView,EndOfBuffer:ScrollView'
  call setwinvar(l:bar_winnr, '&winhighlight', l:winhighlight)
  let l:winblend = s:GetVariable('scrollview_winblend', l:winnr)
  call setwinvar(l:bar_winnr, '&winblend', l:winblend)
  call setwinvar(l:bar_winnr, '&foldcolumn', 0)
  call setwinvar(l:bar_winnr, s:win_var, s:win_val)
  call setwinvar(l:bar_winnr, s:pending_async_removal_var, 0)
  let l:props = {
        \   'parent_winid': l:winid,
        \   'scrollview_winid': l:bar_winid,
        \   'height': l:bar_position.height,
        \   'row': l:bar_position.row,
        \   'col': l:bar_position.col
        \ }
  call setwinvar(l:bar_winnr, s:props_var, l:props)
endfunction

" Given a scrollbar properties dictionary and a target window row, the
" corresponding scrollbar is moved to that row. The row is adjusted (up in
" value, down in visual position) such that the full height of the scrollbar
" remains on screen. Returns the updated scrollbar properties.
function! s:MoveScrollbar(props, row)
  let l:props = copy(a:props)
  let l:max_row = winheight(l:props.parent_winid) - l:props.height + 1
  let l:row = min([a:row, l:max_row])
  let l:options = {
        \   'win': l:props.parent_winid,
        \   'relative': 'win',
        \   'row': l:row - 1,
        \   'col': l:props.col - 1
        \ }
  call nvim_win_set_config(a:props.scrollview_winid, l:options)
  let l:props.row = l:row
  call setwinvar(l:props.scrollview_winid, s:props_var, l:props)
  return l:props
endfunction

function! s:IsScrollViewWindow(winid) abort
  if s:IsOrdinaryWindow(a:winid)
    return 0
  endif
  if getwinvar(win_id2win(a:winid), s:win_var, '') !=# s:win_val
    return 0
  endif
  let l:bufnr = winbufnr(a:winid)
  return l:bufnr ==# s:bar_bufnr
endfunction

function! s:GetScrollViewWindows() abort
  let l:result = []
  for l:winnr in range(1, winnr('$'))
    let l:winid = win_getid(l:winnr)
    if s:IsScrollViewWindow(l:winid)
      call add(l:result, l:winid)
    endif
  endfor
  return l:result
endfunction

function! s:CloseScrollViewWindow(winid) abort
  let l:winid = a:winid
  " The floating window may have been closed (e.g., :only/<ctrl-w>o, or
  " intentionally deleted prior to the removal callback in order to reduce
  " motion blur).
  if getwininfo(l:winid) ==# []
    return
  endif
  if !s:IsScrollViewWindow(l:winid)
    return
  endif
  silent! noautocmd call s:lua_module.close_window(l:winid)
endfunction

" Sets global state that is assumed by the core functionality and returns a
" state that can be used for restoration.
function! s:Init() abort
  let l:state = {
        \   'previous_winid': win_getid(winnr('#')),
        \   'initial_winid': win_getid(winnr()),
        \   'belloff': &belloff,
        \   'eventignore': &eventignore,
        \   'winwidth': &winwidth,
        \   'winheight': &winheight,
        \   'mode': mode()
        \ }
  " Disable the bell (e.g., for invalid cursor movements, trying to navigate
  " to a next fold, when no fold exists).
  set belloff=all
  set eventignore=all
  " Minimize winwidth and winheight so that changing the current window
  " doesn't unexpectedly cause window resizing.
  let &winwidth = max([1, &winminwidth])
  let &winheight = max([1, &winminheight])
  if s:IsSelectMode(l:state.mode)
    " Temporarily switch from select-mode to visual-mode, so that 'normal!'
    " commands can be executed properly.
    execute "normal! \<c-g>"
  endif
  return l:state
endfunction

function! s:Restore(state) abort
  " Restore the previous window so that <c-w>p and winnr('#') function as
  " expected, and so that plugins that utilize previous windows (e.g., CtrlP)
  " function properly. If the current window is the same as the initial
  " window, set the same previous window. If the current window differs from
  " the initial window, use the initial window for setting the previous
  " window.
  " WARN: Since the current window is changed, 'eventignore' should not be
  " restored until after.
  let l:current_winid = win_getid(winnr())
  if l:current_winid ==# a:state.initial_winid
    call win_gotoid(a:state.previous_winid)
  else
    call win_gotoid(a:state.initial_winid)
  endif
  call win_gotoid(l:current_winid)
  " Switch back to select mode where applicable.
  if l:current_winid ==# a:state.initial_winid
    if s:IsSelectMode(a:state.mode)
      if s:IsVisualMode(mode())
        execute "normal! \<c-g>"
      else
        " WARN: this scenario should not arise, and is not handled.
      endif
    endif
  endif
  " Restore options.
  let &belloff = a:state.belloff
  let &eventignore = a:state.eventignore
  let &winwidth = a:state.winwidth
  let &winheight = a:state.winheight
endfunction

" Returns a dictionary that maps window ID to a dictionary of corresponding
" window options.
function! s:GetWindowsOptions() abort
  let l:wins_options = {}
  for l:winid in s:GetOrdinaryWindows()
    let l:wins_options[l:winid] = getwinvar(l:winid, '&')
  endfor
  return l:wins_options
endfunction

" Restores windows options from a dictionary that maps window ID to a
" dictionary of corresponding window options.
function! s:RestoreWindowsOptions(wins_options) abort
  for [l:winid, l:options] in items(a:wins_options)
    if getwininfo(l:winid) ==# [] | continue | endif
    for [l:key, l:value] in items(l:options)
      if getwinvar(l:winid, '&' . l:key) !=# l:value
        silent! call setwinvar(l:winid, '&' . l:key, l:value)
      endif
    endfor
  endfor
endfunction

" Get input characters---including mouse clicks and drags---from the input
" stream. Characters are read until the input stream is empty. Returns a
" 2-tuple with a string representation of the characters, along with a list of
" dictionaries that include the following fields:
"   1) char
"   2) str_idx
"   3) charmod
"   4) mouse_winid
"   5) mouse_row
"   6) mouse_col
" The mouse values are 0 when there was no mouse event.
function! s:ReadInputStream() abort
  " An overlay is displayed in each window so that mouse position can be
  " properly determined. Otherwise, v:mouse_lnum and v:mouse_col may not
  " correspond to the actual position of the click (e.g., when there is a
  " sign/number/relativenumber/fold column, when lines span multiple screen
  " rows from wrapping, or when the last line of the buffer is not at the last
  " line of the window due to a short document or scrolling past the end).
  " XXX: If/when Vim's getmousepos is ported to Neovim, an overlay would not
  " be necessary. That function would return the necessary information, making
  " most of the steps in this function unnecessary.

  " === Configure overlay ===
  if s:overlay_bufnr ==# -1 || !bufexists(s:overlay_bufnr)
    let s:overlay_bufnr = nvim_create_buf(0, 1)
    call setbufvar(s:overlay_bufnr, '&modifiable', 0)
    call setbufvar(s:overlay_bufnr, '&buftype', 'nofile')
    call setbufvar(s:overlay_bufnr, '&swapfile', 0)
    call setbufvar(s:overlay_bufnr, '&bufhidden', 'hide')
    call setbufvar(s:overlay_bufnr, '&buflisted', 0)
  endif
  let l:init_winid = win_getid()
  let l:target_wins = s:GetOrdinaryWindows()

  " Make sure that the buffer size is at least as big as the largest window.
  " Use 'lines' option for this, since a window height can't exceed this.
  let l:overlay_height = getbufinfo(s:overlay_bufnr)[0].linecount
  if &g:lines ># l:overlay_height
    call setbufvar(s:overlay_bufnr, '&modifiable', 1)
    let l:delta = &g:lines - l:overlay_height
    call nvim_buf_set_lines(s:overlay_bufnr, 0, 0, 0, repeat([''], l:delta))
    call setbufvar(s:overlay_bufnr, '&modifiable', 0)
    let l:overlay_height = &g:lines
  endif

  " === Save state and load overlay ===
  let l:win_states = {}
  let l:buf_states = {}
  for l:winid in l:target_wins
    let l:bufnr = winbufnr(l:winid)
    call win_gotoid(l:winid)
    let l:view = winsaveview()
    call win_gotoid(l:init_winid)
    " All buffer and window variables are restored; not just those that were
    " manually modified. This is because some are automatically modified, like
    " 'conceallevel', which was noticed when testing the functionality on help
    " pages, and confirmed further for 'concealcursor' and 'foldenable'.
    let l:win_state = {
          \   'bufnr': l:bufnr,
          \   'win_options': getwinvar(l:winid, '&'),
          \   'view': l:view
          \ }
    let l:win_states[l:winid] = l:win_state
    " Only save the buffer state when it is first visited. If multiple windows
    " have the same buffer, the options would already be modified after
    " visiting the first window with that buffer.
    if !has_key(l:buf_states, l:bufnr)
      let l:buf_state = getbufvar(l:bufnr, '&')
      let l:buf_states[l:bufnr] = l:buf_state
    endif
    " Set options on buffer. This is outside the preceding if-block, since a
    " necessary setting (e.g., removing buftype=help below) may not be applied
    " if only the first window is considered (and it doesn't have a fold, for
    " the running example).
    call setbufvar(l:bufnr, '&bufhidden', 'hide')
    " Temporarily change buftype=help to buftype=<empty> so that mouse
    " interactions don't result in manual folds being deleted from help pages.
    " WARN: 'buftype' is set to 'help' when the state is restored later in
    " this function, which ignores Vim's and Neovim's warnings on setting
    " buftype=help.
    "   Vim: "you are not supposed to set this manually"
    "        - commit 071d427 added this text on Jun 13, 2004
    "   Neovim: "do not set this manually"
    "        - commit 2e1217d changed Vim's text on Nov 10, 2016
    " No observed consequential side-effects were encountered when setting
    " buftype=help in this scenario. The change in warning text for Neovim may
    " have been intended to reduce the text to a single line.
    if getbufvar(l:bufnr, '&buftype') ==# 'help' && s:WindowHasFold(l:winid)
      call setbufvar(l:bufnr, '&buftype', '')
    endif
    " Change buffer
    keepalt keepjumps call nvim_win_set_buf(l:winid, s:overlay_bufnr)
    keepjumps call nvim_win_set_cursor(l:winid, [1, 0])
    " Set options on overlay window/buffer.
    call setwinvar(l:winid, '&number', 0)
    call setwinvar(l:winid, '&relativenumber', 0)
    call setwinvar(l:winid, '&foldcolumn', 0)
    call setwinvar(l:winid, '&signcolumn', 'no')
  endfor

  " === Obtain inputs ===
  let l:chars = []
  let l:chars_props = []
  let l:str_idx = 0  " in bytes
  while 1
    try
      let l:char = getchar()
    catch
      " E.g., <c-c>
      let l:char = "\<esc>"
    finally
      " For Vim on Cygwin, pressing <c-c> during getchar() does not raise
      " "Vim:Interrupt". Handling for such a scenario is added here as a
      " precaution, by converting to <esc>.
      if l:char ==# "\<c-c>"
        let l:char = "\<esc>"
      endif
    endtry
    let l:charmod = getcharmod()
    if type(l:char) ==# v:t_number
      let l:char = nr2char(l:char)
    endif
    call add(l:chars, l:char)
    let l:char_props = {
          \   'char' : l:char,
          \   'str_idx': l:str_idx,
          \   'charmod': l:charmod,
          \   'mouse_winid': v:mouse_winid,
          \   'mouse_row': v:mouse_lnum,
          \   'mouse_col': v:mouse_col
          \ }
    let l:str_idx += strlen(l:char)
    call add(l:chars_props, l:char_props)
    " Break if there are no more items on the input stream.
    if !getchar(1)
      break
    endif
  endwhile
  let l:string = join(l:chars, '')
  let l:result = [l:string, l:chars_props]

  " === Remove overlay and restore state ===
  for l:winid in l:target_wins
    let l:state = l:win_states[l:winid]
    keepalt keepjumps call nvim_win_set_buf(l:winid, l:state.bufnr)
    " Restore window state.
    for [l:key, l:value] in items(l:state.win_options)
      if getwinvar(l:winid, '&' . l:key) !=# l:value
        call setwinvar(l:winid, '&' . l:key, l:value)
      endif
    endfor
    call win_gotoid(l:winid)
    keepjumps call winrestview(l:state.view)
    call win_gotoid(l:init_winid)
  endfor
  " Restore buffer state.
  for [l:bufnr, l:buf_state] in items(l:buf_states)
    " Dictionary keys are saved as strings. Convert back to number, since
    " getbufvar and setbufvar both depend on type information (i.e., a string
    " refers to a buffer name).
    let l:bufnr = str2nr(l:bufnr)
    for [l:key, l:value] in items(l:buf_state)
      if getbufvar(l:bufnr, '&' . l:key) !=# l:value
        call setbufvar(l:bufnr, '&' . l:key, l:value)
      endif
    endfor
  endfor

  " === Return result ===
  return l:result
endfunction

" Returns an array that maps window rows to the topline that corresponds to a
" scrollbar at that row.
function! s:TopLineLookup(winid) abort
  let l:winid = a:winid
  let l:winnr = win_id2win(l:winid)
  let l:scrollview_mode = s:ScrollViewMode(l:winnr)
  let l:topline_lookup = []
  if l:scrollview_mode !=# 'simple'
    " Handling for virtual mode or an unknown mode.
    let l:topline_lookup = s:lua_module.virtual_topline_lookup(l:winid)
    " Lua only has floats. Convert to integer as a precaution.
    for l:idx in range(len(l:topline_lookup))
      let l:topline_lookup[l:idx] = float2nr(l:topline_lookup[l:idx])
    endfor
  else
    let l:bufnr = winbufnr(l:winid)
    let l:line_count = nvim_buf_line_count(l:bufnr)
    let l:winheight = winheight(l:winid)
    for l:row in range(1, l:winheight)
      let l:proportion = s:NumberToFloat(l:row - 1) / (l:winheight - 1)
      let l:topline = float2nr(round(l:proportion * (l:line_count - 1))) + 1
      call add(l:topline_lookup, l:topline)
    endfor
  endif
  return l:topline_lookup
endfunction

" Scrolls the window so that the specified line number is at the top.
function! s:SetTopLine(winid, linenr) abort
  " WARN: Unlike other functions that move the cursor (e.g., VirtualLineCount,
  " VirtualProportionLine), a window workspace should not be used, as the
  " cursor and viewport changes here are intended to persist.
  let l:winid = a:winid
  let l:linenr = a:linenr
  let l:init_winid = win_getid()
  call win_gotoid(l:winid)
  let l:init_line = line('.')
  execute 'keepjumps normal! ' . l:linenr . 'G'
  let l:topline = s:LineRange(l:winid)[0]
  " Use virtual lines to figure out how much to scroll up. winline() doesn't
  " accommodate wrapped lines.
  let l:virtual_line = s:VirtualLineCount(l:winid, l:topline, line('.'))
  if l:virtual_line ># 1
    execute 'keepjumps normal! ' . (l:virtual_line - 1) . "\<c-e>"
  endif
  unlet l:topline  " topline may no longer be correct
  let l:botline = s:LineRange(l:winid)[1]
  if l:botline ==# line('$')
    " If the last buffer line is on-screen, position that line at the bottom
    " of the window.
    keepjumps normal! Gzb
  endif
  " Position the cursor as if all scrolling was conducted with <ctrl-e> and/or
  " <ctrl-y>. H and L are used to get topline and botline instead of
  " getwininfo, to prevent jumping to a line that could result in a scroll if
  " scrolloff>0.
  keepjumps normal! H
  let l:effective_top = line('.')
  keepjumps normal! L
  let l:effective_bottom = line('.')
  if l:init_line <# l:effective_top
    " User scrolled down.
    keepjumps normal! H
  elseif l:init_line ># l:effective_bottom
    " User scrolled up.
    keepjumps normal! L
  else
    " The initial line is still on-screen.
    execute 'keepjumps normal! ' . l:init_line . 'G'
  endif
  call win_gotoid(l:init_winid)
endfunction

" Returns scrollview properties for the specified window. An empty dictionary
" is returned if there is no corresponding scrollbar.
function! s:GetScrollViewProps(winid) abort
  let l:winid = a:winid
  for l:scrollview_winid in s:GetScrollViewWindows()
    let l:props = getwinvar(l:scrollview_winid, s:props_var)
    if l:props.parent_winid ==# l:winid
      return l:props
    endif
  endfor
  return {}
endfunction

" With no argument, remove all bars. Otherwise, remove the specified list of
" bars. Global state is initialized and restored.
function! s:RemoveBars(...) abort
  if s:bar_bufnr ==# -1 | return | endif
  let l:state = s:Init()
  try
    let l:target_wins = a:0 ># 0 ? a:1 : s:GetScrollViewWindows()
    for l:winid in l:target_wins
      call s:CloseScrollViewWindow(l:winid)
    endfor
  catch
  finally
    call s:Restore(l:state)
  endtry
endfunction

" Remove scrollbars if InCommandLineWindow is true. This fails when called
" from the CmdwinEnter event (some functionality, like nvim_win_close,
" cannot be used from the command line window), but works during the
" transition to the command line window (from the WinEnter event).
function! s:RemoveIfCommandLineWindow() abort
  if s:InCommandLineWindow()
    silent! call s:RemoveBars()
  endif
endfunction

" Refreshes scrollbars. There is an optional argument that specifies whether
" removing existing scrollbars is asynchronous (defaults to true). Global
" state is initialized and restored.
function! s:RefreshBars(...) abort
  let l:async_removal = 1
  if a:0 ># 0
    let l:async_removal = a:1
  endif
  let l:state = s:Init()
  try
    if s:InCommandLineWindow()
      return
    endif
    " Remove any scrollbars that are pending asynchronous removal. This
    " reduces the appearance of motion blur that results from the accumulation
    " of windows for asynchronous removal (e.g., when CPU utilization is
    " high).
    for l:winid in s:GetScrollViewWindows()
      if getwinvar(l:winid, s:pending_async_removal_var)
        call s:CloseScrollViewWindow(l:winid)
      endif
    endfor
    " Existing windows are determined before adding new windows, but removed
    " later (they have to be removed after adding to prevent flickering from
    " the delay between removal and adding).
    let l:existing_wins = s:GetScrollViewWindows()
    let l:target_wins = []
    let l:current_only =
          \ s:GetVariable('scrollview_current_only', winnr(), 'tg')
    let l:target_wins =
          \ l:current_only ? [win_getid(winnr())] : s:GetOrdinaryWindows()
    let l:start_reltime = reltime()
    for l:winid in l:target_wins
      call s:ShowScrollbar(l:winid)
    endfor
    " The elapsed microseconds for showing scrollbars.
    let l:elapsed_micro = s:ReltimeToMicroseconds(reltime(l:start_reltime))
    if g:scrollview_refresh_time ># -1
          \ && l:elapsed_micro ># g:scrollview_refresh_time * 1000
      let g:scrollview_refresh_time_exceeded = 1
    end
    if l:async_removal
      " Remove bars asynchronously to prevent flickering (e.g., when there are
      " folds and mode='virtual'). Even when nvim_win_close is called
      " synchronously after the code that adds the other windows, the window
      " removal still happens earlier in time, as confirmed by using
      " 'writedelay'. Even with asynchronous execution, the call to
      " timer_start must still occur after the code for the window additions.
      for l:winid in l:existing_wins
        call setwinvar(win_id2win(l:winid), s:pending_async_removal_var, 1)
      endfor
      " RemoveBars is used instead of CloseScrollViewWindow for global state
      " initialization and restoration.
      let l:cmd = 'silent! call s:RemoveBars(' . string(l:existing_wins) . ')'
      call timer_start(0, {-> execute(l:cmd)})
    else
      for l:winid in l:existing_wins
        call s:CloseScrollViewWindow(l:winid)
      endfor
    endif
  catch
    " Use a catch block, so that unanticipated errors don't interfere. The
    " worst case scenario is that bars won't be shown properly, which was
    " deemed preferable to an obscure error message that can be interrupting.
  finally
    call s:Restore(l:state)
  endtry
endfunction

function! s:RefreshBarsAsyncCallback(timer_id) abort
  let s:pending_async_refresh_count -= 1
  if s:pending_async_refresh_count ># 0
    " If there are asynchronous refreshes that will occur subsequently, don't
    " execute this one.
    return
  endif
  " ScrollView may have already been disabled by time this callback executes
  " asynchronously.
  if s:scrollview_enabled
    call s:RefreshBars()
  endif
endfunction

" This function refreshes the bars asynchronously. This works better than
" updating synchronously in various scenarios where updating occurs in an
" intermediate state of the editor (e.g., when closing a command-line window),
" which can result in bars being placed where they shouldn't be.
" WARN: For debugging, it's helpful to use synchronous refreshing, so that
" e.g., echom works as expected.
function! s:RefreshBarsAsync() abort
  let s:pending_async_refresh_count += 1
  call timer_start(0, function('s:RefreshBarsAsyncCallback'))
endfunction

" *************************************************
" * Main (entry points)
" *************************************************

" INFO: Asynchronous refreshing was originally used to work around issues
" (e.g., getwininfo(winid)[0].botline not updated yet in a synchronous
" context). However, it's now primarily utilized because it makes the UI more
" responsive and it permits redundant refreshes to be dropped (e.g., for mouse
" wheel scrolling).

function! scrollview#ScrollViewEnable() abort
  let s:scrollview_enabled = 1
  augroup scrollview
    autocmd!
    " === Scrollbar Removal ===

    " For the duration of command-line window usage, there should be no bars.
    " Without this, bars can possibly overlap the command line window. This
    " can be problematic particularly when there is a vertical split with the
    " left window's bar on the bottom of the screen, where it would overlap
    " with the center of the command line window. It was not possible to use
    " CmdwinEnter, since the removal has to occur prior to that event. Rather,
    " this is triggered by the WinEnter event, just prior to the relevant
    " funcionality becoming unavailable.
    autocmd WinEnter * :call s:RemoveIfCommandLineWindow()
    " The following error can arise when the last window in a tab is going to
    " be closed, but there are still open floating windows, and at least one
    " other tab.
    "   > "E5601: Cannot close window, only floating window would remain"
    " Neovim Issue #11440 is open to address this. As of 2020/12/12, this
    " issue is a 0.6 milestone.
    " The autocmd below removes bars subsequent to :quit, :wq, or :qall (and
    " also ZZ and ZQ), to avoid the error. However, the error will still arise
    " when <ctrl-w>c or :close are used. To avoid the error in those cases,
    " <ctrl-w>o can be used to first close the floating windows, or
    " alternatively :tabclose can be used (or one of the alternatives handled
    " with the autocmd, like ZQ).
    autocmd QuitPre * :call s:RemoveBars()

    " === Scrollbar Refreshing ===

    " The following handles bar refreshing when changing the current window.
    autocmd WinEnter,TermEnter * :call s:RefreshBarsAsync()
    " The following restores bars after leaving the command-line window.
    " Refreshing must be asynchronous, since the command line window is still
    " in an intermediate state when the CmdwinLeave event is triggered.
    autocmd CmdwinLeave * :call s:RefreshBarsAsync()
    " The following handles scrolling events, which could arise from various
    " actions, including resizing windows, movements (e.g., j, k), or
    " scrolling (e.g., <ctrl-e>, zz).
    autocmd WinScrolled * :call s:RefreshBarsAsync()
    " The following handles the case where text is pasted. TextChangedI is not
    " necessary since WinScrolled will be triggered if there is corresponding
    " scrolling.
    autocmd TextChanged * :call s:RefreshBarsAsync()
    " The following handles when :e is used to load a file. The asynchronous
    " version handles a case where :e is used to reload an existing file, that
    " is already scrolled. This avoids a scenario where the scrollbar is
    " refreshed while the window is an intermediate state, resulting in the
    " scrollbar moving to the top of the window.
    autocmd BufWinEnter * :call s:RefreshBarsAsync()
    " The following is used so that bars are shown when cycling through tabs.
    autocmd TabEnter * :call s:RefreshBarsAsync()
    autocmd VimResized * :call s:RefreshBarsAsync()
  augroup END
  " The initial refresh is asynchronous, since :ScrollViewEnable can be used
  " in a context where Neovim is in an intermediate state. For example, for
  " ':bdelete | ScrollViewEnable', with synchronous processing, the 'topline'
  " and 'botline' in getwininfo's results correspond to the existing buffer
  " that :bdelete was called on.
  call s:RefreshBarsAsync()
endfunction

function! scrollview#ScrollViewDisable() abort
  let l:winid = win_getid(winnr())
  let l:state = s:Init()
  try
    if s:InCommandLineWindow()
      echohl ErrorMsg
      echo 'nvim-scrollview: Cannot disable from command-line window'
      echohl None
      return
    endif
    let s:scrollview_enabled = 0
    augroup scrollview
      autocmd!
    augroup END
    " Remove scrollbars from all tabs.
    tabdo silent! call s:RemoveBars()
  finally
    call win_gotoid(l:winid)
    call s:Restore(l:state)
  endtry
endfunction

function! scrollview#ScrollViewRefresh() abort
  if s:scrollview_enabled
    " This refresh is asynchronous to keep interactions responsive (e.g.,
    " mouse wheel scrolling, as redundant async refreshes are dropped). If
    " scenarios necessitate synchronous refreshes, the interface would have to
    " be updated (e.g., :ScrollViewRefresh --sync) to accommodate (as there is
    " currently only a single refresh command and a single refresh <plug>
    " mapping, both utilizing whatever is implemented here).
    call s:RefreshBarsAsync()
  endif
endfunction

" 'button' can be 'left', 'middle', 'right', 'x1', or 'x2'.
function! scrollview#HandleMouse(button) abort
  if !s:Contains(['left', 'middle', 'right', 'x1', 'x2'], a:button)
    throw 'Unsupported button: ' . a:button
  endif
  let l:state = s:Init()
  let l:wins_options = s:GetWindowsOptions()
  " virtual_line_count would return the same values for the same arguments,
  " for the duration of mouse drag scrolling, so use memoization.
  call s:lua_module.start_memoize()
  try
    let l:mousedown = eval(printf('"\<%smouse>"', a:button))
    let l:mouseup = eval(printf('"\<%srelease>"', a:button))
    " Re-send the click, so its position can be obtained from a subsequent
    " call to getchar().
    " XXX: If/when Vim's getmousepos is ported to Neovim, the position of the
    " initial click would be available without getchar(), but would require
    " some refactoring below to accommodate.
    call feedkeys(l:mousedown, 'ni')
    " Mouse handling is not relevant in the command line window since
    " scrollbars are not shown. Additionally, the overlay cannot be closed
    " from that mode.
    if s:InCommandLineWindow()
      return
    endif
    " Temporarily change foldmethod=syntax to foldmethod=manual to prevent
    " lagging (Issue #20). This could result in a brief change to the text
    " displayed for closed folds, due to the 'foldtext' function using
    " specific text for syntax folds. This side-effect was deemed a preferable
    " tradeoff to lagging.
    for l:winid in keys(l:wins_options)
      if getwinvar(l:winid, '&foldmethod') ==# 'syntax'
        call setwinvar(l:winid, '&foldmethod', 'manual')
      endif
    endfor
    let l:count = 0
    let l:winid = 0  " The target window ID for a mouse scroll.
    let l:winnr = 0  " The target window number.
    let l:bufnr = 0  " The target buffer number.
    let l:idx = 0
    let [l:string, l:chars_props] = ['', []]
    " Computing this prior to the first mouse event could distort the location
    " since this could be an expensive operation (and the mouse could move).
    let l:topline_lookup = v:null
    while 1
      while 1
        let l:idx += 1
        if l:idx >=# len(l:chars_props)
          let l:idx = 0
          let [l:string, l:chars_props] = s:ReadInputStream()
        endif
        let l:char_props = l:chars_props[l:idx]
        let l:str_idx = l:char_props.str_idx
        let l:char = l:char_props.char
        let l:mouse_winid = l:char_props.mouse_winid
        let l:mouse_row = l:char_props.mouse_row
        let l:mouse_col = l:char_props.mouse_col
        " The following code skips mouse drags that have already been followed
        " by subsequent mouse drags.
        if !s:Contains([l:mousedown, l:mouseup], l:char)
              \ && l:mouse_winid !=# 0
          if l:idx + 1 <# len(l:chars_props)
            let l:next = l:chars_props[l:idx + 1]
            if !s:Contains([l:mousedown, l:mouseup], l:next.char)
                  \ && l:next.mouse_winid !=# 0
              continue
            endif
          endif
        endif
        break
      endwhile
      if l:char ==# "\<esc>"
        call feedkeys(l:string[l:str_idx + strlen(l:char):], 'ni')
        return
      endif
      " In select-mode, mouse usage results in the mode intermediately
      " switching to visual mode, accompanied by a call to this function.
      " After the initial mouse event, the next getchar() character is
      " <80><f5>X. This is "Used for switching Select mode back on after a
      " mapping or menu" (https://github.com/vim/vim/blob/
      " c54f347d63bcca97ead673d01ac6b59914bb04e5/src/keymap.h#L84-L88,
      " https://github.com/vim/vim/blob/
      " c54f347d63bcca97ead673d01ac6b59914bb04e5/src/getchar.c#L2660-L2672)
      " Ignore this character after scrolling has started.
      " NOTE: "\x80\xf5X" (hex) ==# "\200\365X" (octal)
      if l:char ==# "\x80\xf5X" && l:count ># 0
        continue
      endif
      if l:mouse_winid ==# 0
        " There was no mouse event.
        call feedkeys(l:string[l:str_idx:], 'ni')
        return
      endif
      if l:char ==# l:mouseup
        if l:count ==# 0
          " No initial mousedown was captured.
          call feedkeys(l:string[l:str_idx:], 'ni')
        elseif l:count ==# 1
          " A scrollbar was clicked, but there was no corresponding drag.
          " Allow the interaction to be processed as it would be with no
          " scrollbar.
          call feedkeys(l:mousedown . l:string[l:str_idx:], 'ni')
        else
          " A scrollbar was clicked and there was a corresponding drag.
          " 'feedkeys' is not called, since the full mouse interaction has
          " already been processed. The current window (from prior to
          " scrolling) is not changed.
        endif
        return
      endif
      if l:count ==# 0
        let l:props = s:GetScrollViewProps(l:mouse_winid)
        if l:props ==# {}
          " There was no scrollbar in the window where a click occurred.
          call feedkeys(l:string[l:str_idx:], 'ni')
          return
        endif
        " Add 1 cell horizonal padding for grabbing the scrollbar. Don't do
        " this when the padding would extend past the window, as it will
        " interfere with dragging the vertical separator to resize the window.
        let l:lpad = l:props.col ># 1 ? 1 : 0
        let l:rpad = l:props.col <# winwidth(l:mouse_winid) ? 1 : 0
        if l:mouse_row <# l:props.row
              \ || l:mouse_row >=# l:props.row + l:props.height
              \ || l:mouse_col <# l:props.col - l:lpad
              \ || l:mouse_col ># l:props.col + l:rpad
          " The click was not on a scrollbar.
          call feedkeys(l:string[l:str_idx:], 'ni')
          return
        endif
        " The click was on a scrollbar.
        " It's possible that the clicked scrollbar is out-of-sync. Refresh the
        " scrollbars and check if the mouse is still over a scrollbar. If not,
        " ignore all mouse events until a mouseup. This approach was deemed
        " preferable to refreshing scrollbars initially, as that could result
        " in unintended clicking/dragging where there is no scrollbar.
        call s:RefreshBars(0)
        redraw
        let l:props = s:GetScrollViewProps(l:mouse_winid)
        if l:props ==# {} || l:mouse_row <# l:props.row
              \ || l:mouse_row >=# l:props.row + l:props.height
          while getchar() !=# l:mouseup | endwhile | return
        endif
        " By this point, the click on a scrollbar was successful.
        if s:IsVisualMode(mode())
          " Exit visual mode.
          execute "normal! \<esc>"
        endif
        let l:winid = l:mouse_winid
        let l:winnr = win_id2win(l:winid)
        let l:bufnr = winbufnr(l:winnr)
        let l:scrollbar_offset = l:props.row - l:mouse_row
        let l:previous_row = l:props.row
      endif
      let l:winheight = winheight(l:winid)
      let l:mouse_winrow = getwininfo(l:mouse_winid)[0].winrow
      let l:winrow = getwininfo(l:winid)[0].winrow
      let l:window_offset = l:mouse_winrow - l:winrow
      let l:row = l:mouse_row + l:window_offset + l:scrollbar_offset
      let l:row = min([l:row, l:winheight - l:props.height + 1])
      let l:row = max([1, l:row])
      " Only update scrollbar if the row changed.
      if l:previous_row !=# l:row
        if l:topline_lookup is v:null
          let l:topline_lookup = s:TopLineLookup(l:winid)
        endif
        let l:topline = l:topline_lookup[l:row - 1]
        let l:topline = max([1, l:topline])
        if l:row ==# 1
          " If the scrollbar was dragged to the top of the window, always show
          " the first line.
          let l:topline = 1
        elseif l:row + l:props.height - 1 >=# l:winheight
          " If the scrollbar was dragged to the bottom of the window, always
          " show the bottom line.
          let l:topline = nvim_buf_line_count(l:bufnr)
        endif
        call s:SetTopLine(l:winid, l:topline)
        if getwinvar(l:winid, '&scrollbind')
              \ || getwinvar(l:winid, '&cursorbind')
          " Refresh other window scrollbars when scrollbind/cursorbind is on.
          " WARN: This should be before MoveScrollbar, so the dragged
          " scrollbar always stays under the mouse when
          " g:scrollview_mode=simple.
          call s:RefreshBars(0)
          let l:props = s:GetScrollViewProps(l:winid)
        endif
        let l:props = s:MoveScrollbar(l:props, l:row)
        redraw
      endif
      let l:previous_row = l:row
      let l:count += 1
    endwhile
  catch
  finally
    call s:lua_module.stop_memoize()
    call s:lua_module.reset_memoize()
    call s:RestoreWindowsOptions(l:wins_options)
    call s:Restore(l:state)
  endtry
endfunction
