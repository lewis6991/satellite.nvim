" WARN: Sometimes 1-indexing is used (primarily for mutual Vim/Neovim API
" calls) and sometimes 0-indexing (primarily for Neovim-specific API calls).

" *************************************************
" * Globals
" *************************************************

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

" *************************************************
" * Utils
" *************************************************

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

" Executes a list of commands in the context of the specified window.
" If a local result variable is set, it will be returned.
" WARN: Loops within the specified commands cannot be executed, due to their
" interaction with the for loop in this function. To resolve, instead of
" putting loops into the commands, extract the loops to separate functions,
" and have the specified commands call those functions.
function! s:WinExecute(winid, commands) abort
  let l:current_winid = win_getid(winnr())
  call win_gotoid(a:winid)
  for l:command in a:commands
    execute l:command
  endfor
  call win_gotoid(l:current_winid)
  if exists('l:result')
    return l:result
  else
    return
  endif
endfunction

function! s:NumberToFloat(number) abort
  return a:number + 0.0
endfunction

" *************************************************
" * Core
" *************************************************

" Returns true for ordinary windows (not floating and not external), and
" false otherwise.
function! s:IsOrdinaryWindow(winid) abort
  let l:config = nvim_win_get_config(a:winid)
  let l:not_external = !get(l:config, 'external', 0)
  let l:not_floating = get(l:config, 'relative', '') ==# ''
  return l:not_external && l:not_floating
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

" Returns the window column where the buffer's text begins. This may be
" negative due to horizontal scrolling. This may be greater than one due to
" the sign column and 'number' column.
function! s:BufferTextBeginsColumn(winid) abort
  " The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  let l:commands = [
        \   'let l:wrap = &l:wrap',
        \   'setlocal nowrap',
        \   'let l:result = wincol() - virtcol(".") + 1',
        \   'let &l:wrap = l:wrap'
        \ ]
  let l:result = s:WinExecute(a:winid, l:commands)
  return l:result
endfunction

" Returns the window column where the view of the buffer begins. This can be
" greater than one due to the sign column and 'number' column.
function! s:BufferViewBeginsColumn(winid) abort
  " The calculation assumes lines don't wrap, so 'nowrap' is temporarily set.
  let l:commands = [
        \   'let l:wrap = &l:wrap',
        \   'setlocal nowrap',
        \   'let l:result = wincol() - virtcol(".")'
        \       . ' + winsaveview().leftcol + 1',
        \   'let &l:wrap = l:wrap'
        \ ]
  let l:result = s:WinExecute(a:winid, l:commands)
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

" Returns the count of visible lines between the specified start and end lines
" (both inclusive), in the specified window. A closed fold counts as one
" visible line. '$' can be used as the end line, to represent the last line.
" The function currently depends on a Lua function for faster execution, as
" there is a loop over all lines in the specified window's buffer.
" TODO: Using Vim fold movements (zj, zk), instead of looping over every line,
" may be a way to speed this up further, but would presumably require a more
" complicated implementation.
function! s:VisibleLineCount(winid, start, end) abort
  let l:result = -1
  let l:current_winid = win_getid(winnr())
  call win_gotoid(a:winid)
  let l:end = a:end
  if type(l:end) ==# v:t_string && l:end ==# '$'
    let l:end = line('$')
  endif
  let l:module = luaeval('require("scrollview")')
  let l:result = l:module.visible_line_count(a:start, l:end)
  call win_gotoid(l:current_winid)
  return l:result
endfunction

" Calculates the bar position for the specified window. Returns a dictionary
" with a height, row, and col.
function! s:CalculatePosition(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
  let l:bufnr = winbufnr(l:winnr)
  let l:wininfo = getwininfo(l:winid)[0]
  let l:topline = l:wininfo.topline
  " WARN: l:wininfo.botline is not properly updated for some movements (Neovim
  " Issue #13510). Correct behavior depends on this function being executed in
  " an asynchronous context for the corresponding movements (e.g., gg, G).
  " This is handled by having WinScrolled trigger an asychronous refresh.
  let l:botline = l:wininfo.botline
  let l:line_count = nvim_buf_line_count(l:bufnr)
  let l:winheight = winheight(l:winnr)
  let l:winwidth = winwidth(l:winnr)
  let l:mode = s:GetVariable('scrollview_mode', l:winnr)
  if l:mode ==# 'virtual'
    " Update topline, botline, and line_count to correspond to virtual lines,
    " which account for closed folds.
    let l:virtual_counts = {
          \   'before': s:VisibleLineCount(l:winid, 1, l:topline - 1),
          \   'here': s:VisibleLineCount(l:winid, l:topline, l:botline),
          \   'after': s:VisibleLineCount(l:winid, l:botline + 1, '$')
          \ }
    let l:topline = l:virtual_counts.before + 1
    let l:botline = l:virtual_counts.before + l:virtual_counts.here
    let l:line_count = l:virtual_counts.before
          \ + l:virtual_counts.here
          \ + l:virtual_counts.after
  endif
  " l:top is the position for the top of the scrollbar, relative to the
  " window, and 0-indexed.
  let l:top = 0
  if l:line_count ># 1
    let l:top = (l:topline - 1.0) / (l:line_count - 1)
    let l:top = float2nr(round((l:winheight - 1) * l:top))
  endif
  let l:height = l:winheight
  if l:line_count ># l:height
    let l:numerator = l:winheight
    if l:mode ==# 'flexible'
      let l:numerator = l:botline - l:topline + 1
    endif
    let l:height = s:NumberToFloat(l:numerator) / l:line_count
    let l:height = float2nr(ceil(l:height * l:winheight))
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
  let l:wininfo = getwininfo(l:winid)[0]
  " Don't show in terminal mode, since the bar won't be properly updated for
  " insertions.
  if l:wininfo.terminal
    return
  endif
  if l:winheight ==# 0 || l:winwidth ==# 0
    return
  endif
  let l:line_count = nvim_buf_line_count(l:bufnr)
  " Don't show the position bar when all lines are on screen.
  " WARN: See the botline usage warning in CalculatePosition.
  if l:wininfo.botline - l:wininfo.topline + 1 ==# l:line_count
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
  if l:bar_position.col < l:min_valid_col
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
  let l:props = {
        \   'parent_winid': l:winid,
        \   'height': l:bar_position.height,
        \   'row': l:bar_position.row,
        \   'col': l:bar_position.col
        \ }
  call setwinvar(l:bar_winnr, s:props_var, l:props)
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
  " The floating window may have been closed (e.g., :only/<ctrl-w>o).
  if getwininfo(l:winid) ==# []
    return
  endif
  if !s:IsScrollViewWindow(l:winid)
    return
  endif
  silent! noautocmd call nvim_win_close(l:winid, 1)
endfunction

" Sets global state that is assumed by the core functionality and returns a
" state that can be used for restoration.
function! s:Init()
  let l:state = {
        \   'eventignore': &eventignore,
        \   'winwidth': &winwidth,
        \   'winheight': &winheight
        \ }
  " Minimize winwidth and winheight so that changing the current window
  " doesn't unexpectedly cause window resizing.
  set eventignore=all
  let &winwidth = max([1, &winminwidth])
  let &winheight = max([1, &winminheight])
  return l:state
endfunction

function! s:Restore(state)
  let &winwidth = a:state.winwidth
  let &winheight = a:state.winheight
  let &eventignore = a:state.eventignore
endfunction

" Get the next character press, including mouse clicks and drags. Returns a
" dictionary that includes the following fields:
"   1) char
"   2) mouse_winid
"   3) mouse_row
"   4) mouse_col
" The mouse values are 0 when there was no mouse event.
function! s:GetChar() abort
  " An overlay is displayed in each window so that mouse position can be
  " properly determined. Otherwise, lnum may not correspond to the actual
  " position of the click (e.g., when there is a sign/number/relativenumber/fold
  " column, when lines span multiple screen rows from wrapping, or when the last
  " line of the buffer is not at the last line of the window due to a short
  " document or scrolling past the end).

  " === Configure overlay ===
  if s:overlay_bufnr ==# -1 || !bufexists(s:overlay_bufnr)
    let s:overlay_bufnr = nvim_create_buf(0, 1)
    call setbufvar(s:overlay_bufnr, '&modifiable', 0)
    call setbufvar(s:overlay_bufnr, '&buftype', 'nofile')
  endif
  let l:init_winid = win_getid()
  let l:target_wins = []
  for l:winnr in range(1, winnr('$'))
    let l:winid = win_getid(l:winnr)
    if s:IsOrdinaryWindow(l:winid)
      call add(l:target_wins, l:winid)
    endif
  endfor

  " Make sure that the buffer size is at least as big as the largest window.
  let l:overlay_height = getbufinfo(s:overlay_bufnr)[0].linecount
  for l:winid in l:target_wins
    let l:winheight = winheight(l:winid)
    if l:winheight ># l:overlay_height
      call setbufvar(s:overlay_bufnr, '&modifiable', 1)
      let l:delta = l:winheight - l:overlay_height
      call nvim_buf_set_lines(s:overlay_bufnr, 0, 0, 0, repeat([''], l:delta))
      call setbufvar(s:overlay_bufnr, '&modifiable', 0)
      let l:overlay_height = l:winheight
    endif
  endfor

  " === Save state and load overlay ===
  let l:win_states = {}
  for l:winid in l:target_wins
    let l:bufnr = winbufnr(l:winid)
    call win_gotoid(l:winid)
    let l:view = winsaveview()
    call win_gotoid(l:init_winid)
    " All buffer and window variables are restored; not just those that were
    " manually modified. This is because some are automatically modified, like
    " 'conceallevel', which was noticed when testing the functionality on help
    " pages, and confirmed further for 'concealcursor' and 'foldenable'.
    let l:state = {
          \   'bufnr': l:bufnr,
          \   'win_options': getwinvar(l:winid, '&'),
          \   'buf_options': getbufvar(l:bufnr, '&'),
          \   'view': l:view
          \ }
    let l:win_states[l:winid] = l:state
    " Set options on initial buffer.
    call nvim_buf_set_option(l:bufnr, 'bufhidden', 'hide')
    call nvim_win_set_buf(l:winid, s:overlay_bufnr)
    " Set options on overlay window/buffer.
    call nvim_win_set_cursor(l:winid, [1, 0])
    call nvim_win_set_option(l:winid, 'number', v:false)
    call nvim_win_set_option(l:winid, 'relativenumber', v:false)
    call nvim_win_set_option(l:winid, 'foldcolumn', '0')
    call nvim_win_set_option(l:winid, 'signcolumn', 'no')
  endfor

  " === Obtain input ===
  let l:char = getchar()

  " === Remove overlay and restore state ===
  for l:winid in l:target_wins
    let l:state = l:win_states[l:winid]
    call nvim_win_set_buf(l:winid, l:state.bufnr)
    for [l:key, l:value] in items(l:state.win_options)
      if getwinvar(l:winid, '&' . l:key) !=# l:value
        call setwinvar(l:winid, '&' . l:key, l:value)
      endif
    endfor
    for [l:key, l:value] in items(l:state.buf_options)
      if getbufvar(l:bufnr, '&' . l:key) !=# l:value
        call setbufvar(l:bufnr, '&' . l:key, l:value)
      endif
    endfor
    call win_gotoid(l:winid)
    call winrestview(l:state.view)
    call win_gotoid(l:init_winid)
  endfor

  " === Return result ===
  let l:result = {
        \   'char': l:char,
        \   'mouse_winid': v:mouse_winid,
        \   'mouse_row': v:mouse_lnum,
        \   'mouse_col': v:mouse_col
        \ }
  return l:result
endfunction

" *************************************************
" * Main (entry points)
" *************************************************

function! scrollview#RemoveBars() abort
  if s:bar_bufnr ==# -1 | return | endif
  let l:state = s:Init()
  try
    " Remove all existing bars
    for l:winid in s:GetScrollViewWindows()
      call s:CloseScrollViewWindow(l:winid)
    endfor
  catch
  finally
    call s:Restore(l:state)
  endtry
endfunction

" Refreshes scrollbars. There is an optional argument that specifies whether
" removing existing scrollbars is asynchronous (defaults to true).
function! scrollview#RefreshBars(...) abort
  let l:async_removal = 1
  if a:0 ># 0
    let l:async_removal = a:1
  endif
  let l:state = s:Init()
  try
    " Some functionality, like nvim_win_close, cannot be used from the command
    " line window.
    if s:InCommandLineWindow()
      " For the duration of command-line window usage, there will be no bars.
      " Without this, bars can possibly overlap the command line window. This
      " can be problematic particularly when there is a vertical split with the
      " left window's bar on the bottom of the screen, where it would overlap
      " with the center of the command line window. It was not possible to use
      " CmdwinEnter, since the removal has to occur prior to that event.
      " Rather, this is triggered by the WinEnter event, just prior to the
      " relevant funcionality becoming unavailable.
      silent! call scrollview#RemoveBars()
      return
    endif
    " Existing windows are determined before adding new windows, but removed
    " later (they have to be removed after adding to prevent flickering from
    " the delay between removal and adding).
    let l:existing_wins = s:GetScrollViewWindows()
    let l:target_wins = []
    let l:current_only =
          \ s:GetVariable('scrollview_current_only', winnr(), 'tg')
    if l:current_only
      call add(l:target_wins, win_getid(winnr()))
    else
      for l:winnr in range(1, winnr('$'))
        let l:winid = win_getid(l:winnr)
        if s:IsOrdinaryWindow(l:winid)
          call add(l:target_wins, l:winid)
        endif
      endfor
    endif
    for l:winid in l:target_wins
      call s:ShowScrollbar(l:winid)
    endfor
    if l:async_removal
      " Remove bars asynchronously to prevent flickering. Even when
      " nvim_win_close is called synchronously after the code that adds the
      " other windows, the window removal still happens earlier in time, as
      " confirmed by using 'writedelay'. Even with asyncronous execution, the
      " call to timer_start must still occur after the code for the window
      " additions.
      " WARN: The statement is put in a string to prevent a closure whereby
      " the variable used in the lambda will have its value change by the time
      " the code executes. By putting this in a string, the window ID becomes
      " fixed at string-creation time.
      for l:winid in l:existing_wins
        let l:cmd = 'silent! call s:CloseScrollViewWindow(' . l:winid . ')'
        let l:expr = 'call timer_start(0, {-> execute("' . l:cmd . '")})'
        execute l:expr
      endfor
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

function! s:RefreshBarsAsyncCallback(timer_id)
  let s:pending_async_refresh_count -= 1
  if s:pending_async_refresh_count ># 0
    " If there are asynchronous refreshes that will occur subsequently, don't
    " execute this one.
    return
  endif
  call scrollview#RefreshBars()
endfunction

" This function refreshes the bars asynchronously. This works better than
" updating synchronously in various scenarios where updating occurs in an
" intermediate state of the editor (e.g., when closing a command-line window),
" which can result in bars being placed where they shouldn't be.
" WARN: For debugging, it's helpful to use synchronous refreshing, so that
" e.g., echom works as expected.
function! scrollview#RefreshBarsAsync() abort
  let s:pending_async_refresh_count += 1
  call timer_start(0, function('s:RefreshBarsAsyncCallback'))
endfunction

function! scrollview#HandleMouse() abort
  let l:state = s:Init()
  try
    " It's not possible to capture the starting column and line number of a
    " <LeftMouse> event, so it's approximated after the drag event that follows
    " (where the position will be captured since getchar() is used).
    let l:count = 0
    let l:winid = 0  " The target window ID for a mouse scroll.
    let l:winnr = 0  " The target window number for a mouse scroll.
    while 1
      let l:input = s:GetChar()
      let l:char = l:input.char
      let l:mouse_winid = l:input.mouse_winid
      let l:mouse_row = l:input.mouse_row
      let l:mouse_col = l:input.mouse_col
      if l:mouse_winid ==# 0
        " There was no mouse event.
        call feedkeys("\<LeftMouse>" . l:char, 'n')
        return
      endif
      if l:char ==# "\<LeftRelease>"
        if l:count ==# 0
          call feedkeys("\<LeftMouse>\<LeftRelease>", 'n')
        endif
        return
      endif
      if l:count ==# 0
        for l:scrollview_winid in s:GetScrollViewWindows()
          let l:props = getwinvar(l:scrollview_winid, s:props_var)
          if l:props.parent_winid ==# l:mouse_winid
            break
          endif
          unlet l:props
        endfor
        if !exists('l:props')
          " There was no scrollbar in the window where a click occurred.
          call feedkeys("\<LeftMouse>" . l:char, 'n')
          return
        endif
        let l:padding = 1  " Extra horizontal padding for grabbing the scrollbar.
        if l:mouse_row < l:props.row
              \ || l:mouse_row >= l:props.row + l:props.height
              \ || l:mouse_col < l:props.col - l:padding
              \ || l:mouse_col > l:props.col + l:padding
          call feedkeys("\<LeftMouse>" . l:char, 'n')
          return
        endif
        let l:offset = l:mouse_row - l:props.row
        let l:previous_row = 0  " Always refresh for the initial movement.
        let l:winid = l:mouse_winid
        let l:winnr = win_id2win(l:winid)
      endif
      if l:winid !=# l:mouse_winid
        " The current window does not match that of the initial movement.
        continue
      endif
      " Only update scrollbar if the row changed.
      if l:previous_row !=# l:mouse_row
        " TODO: ADD SUPPORT FOR scrollview_mode
        let l:pos = (100 * (l:mouse_row - l:offset)) / winheight(l:props.parent_winid)
        let l:pos = max([1, l:pos])
        let l:init_winid = win_getid()  " The current window.
        call win_gotoid(l:mouse_winid)
        execute 'normal ' . l:pos . '%zt'
        call win_gotoid(l:init_winid)
        call scrollview#RefreshBars(0)
        redraw
      endif
      let l:previous_row = l:mouse_row
      let l:count += 1
    endwhile
  finally
    if get(l:, 'winid', 0) !=# 0
      " Set the scrolled window as the current window.
      call win_gotoid(l:winid)
    endif
    call s:Restore(l:state)
  endtry
endfun
