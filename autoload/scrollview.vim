" WARN: Sometimes 1-indexing is used (primarily for mutual Vim/Neovim API
" calls) and sometimes 0-indexing (primarily for Neovim-specific API calls).

" *************************************************
" * Globals
" *************************************************

" s:bar_winids has the winids of existing bars. An existing value is loaded so
" existing bars can be properly closed when re-sourcing this file.
let s:bar_winids = get(s:, 'bar_winids', [])

" s:bar_bufnr has the bufnr of the first buffer created for a position bar.
" Since there is no text displayed in the buffer, the same buffer can be used
" for multiple floating windows. This also prevents the buffer list from
" getting high from usage of the plugin.
let s:bar_bufnr = get(s:, 'bar_bufnr', -1)

" Keep count of pending async refreshes.
let s:pending_async_refresh_count = 0

" *************************************************
" * Utils
" *************************************************

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

" Executes a list of commands in the context of the specified window.
" Autocommands will not be triggered (unless the commands change eventignore
" accordingly). If a local result variable is set, it will be returned.
" WARN: This differ's from Vim's win_execute, as that triggers autocommands
" when executing a command.
" WARN: Loops within the specified commands cannot be executed, due to their
" interaction with the for loop in this function. To resolve, instead of
" putting loops into the commands, extract the loops to separate functions,
" and have the specified commands call those functions.
function! s:WinExecute(winid, commands) abort
  let l:eventignore = &eventignore
  try
    set eventignore=all
    let l:current_winid = win_getid(winnr())
    call win_gotoid(a:winid)
    for l:command in a:commands
      execute l:command
    endfor
    call win_gotoid(l:current_winid)
  finally
    let &eventignore = l:eventignore
  endtry
  if exists('l:result')
    return l:result
  else
    return
  endif
endfunction

" *************************************************
" * Core
" *************************************************

" Returns true for ordinary windows (not floating and not external), and
" false otherwise.
function! s:IsOrdinaryWindow(winid) abort
  let l:config = nvim_win_get_config(win_getid(a:winid))
  let l:not_external = !get(l:config, 'external', 0)
  let l:not_floating = get(l:config, 'relative', '') ==# ''
  return l:not_external && l:not_floating
endfunction

function! s:InCommandLineWindow() abort
  if mode() ==# 'c'
    return 1
  endif
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
  let l:eventignore = &eventignore
  let l:result = -1
  try
    set eventignore=all
    let l:current_winid = win_getid(winnr())
    call win_gotoid(a:winid)
    let l:end = a:end
    if l:end ==# '$'
      let l:end = line('$')
    endif
    let l:module = luaeval('require("scrollview")')
    let l:result = l:module.visible_line_count(a:start, l:end)
    call win_gotoid(l:current_winid)
  finally
    let &eventignore = l:eventignore
  endtry
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
  let [l:row, l:col] = win_screenpos(l:winnr)
  let l:winheight = winheight(l:winnr)
  let l:winwidth = winwidth(l:winnr)
  " l:top is relative to the window, and 0-indexed.
  let l:top = 0
  if l:line_count ># 1
    let l:top = (l:topline - 1.0) / (l:line_count - 1)
    let l:top = float2nr(round((l:winheight - 1) * l:top))
  endif
  let l:height = l:winheight
  if l:line_count ># l:height
    let l:height = str2float(l:winheight) / l:line_count
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
  " At this point, l:col corresponds the window's leftmost column.
  let l:column = s:GetVariable('scrollview_column', l:winnr)
  let l:base = s:GetVariable('scrollview_base', l:winnr)
  if l:base ==# 'left'
    let l:col += l:column - 1
  elseif l:base ==# 'right'
    let l:col += l:winwidth - l:column
  elseif l:base ==# 'buffer'
    let l:col += l:column - 1
          \ + s:BufferTextBeginsColumn(l:winid) - 1
  else
    " For an unknown base, use the default position (right edge of window).
    let l:col += l:winwidth - 1
  endif
  let l:line = l:row + l:top
  let l:result = {
        \   'height': l:height,
        \   'row': l:line,
        \   'col': l:col
        \ }
  return l:result
endfunction

function! s:ShowScrollbar(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
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
  let l:bar_position = s:CalculatePosition(l:winnr)
  " Don't show the position bar when it would span the entire screen.
  if l:winheight ==# l:bar_position.height
    return
  endif
  " Don't show scrollbar when its column is beyond what's valid.
  let l:min_valid_col = 1
  let l:max_valid_col = l:winwidth
  let l:base = s:GetVariable('scrollview_base', l:winnr)
  if l:base ==# 'buffer'
    let l:min_valid_col = s:BufferViewBeginsColumn(l:winid)
  endif
  let l:col = l:bar_position.col - win_screenpos(l:winnr)[1] + 1
  if l:col <# l:min_valid_col
    return
  endif
  if l:col ># l:winwidth
    return
  endif
  if s:bar_bufnr ==# -1
    let s:bar_bufnr = nvim_create_buf(0, 1)
    call setbufvar(s:bar_bufnr, '&modifiable', 0)
    call setbufvar(s:bar_bufnr, '&filetype', 'scrollview')
    call setbufvar(s:bar_bufnr, '&buftype', 'nofile')
  endif
  let l:options = {
        \   'relative': 'editor',
        \   'focusable': 0,
        \   'style': 'minimal',
        \   'height': l:bar_position.height,
        \   'width': 1,
        \   'row': l:bar_position.row - 1,
        \   'col': l:bar_position.col - 1
        \ }
  let l:bar_winid = nvim_open_win(s:bar_bufnr, 0, l:options)
  call add(s:bar_winids, l:bar_winid)
  " It's not sufficient to just specify Normal highlighting. With just that, a
  " color scheme's specification of EndOfBuffer would be used to color the
  " bottom of the scrollbar.
  let l:winheighlight = 'Normal:ScrollView,EndOfBuffer:ScrollView'
  call setwinvar(l:bar_winid, '&winhighlight', l:winheighlight)
  let l:winblend = s:GetVariable('scrollview_winblend', l:winnr)
  call setwinvar(l:bar_winid, '&winblend', l:winblend)
  call setwinvar(l:bar_winid, '&foldcolumn', 0)
endfunction

function! scrollview#RemoveBars() abort
  " Remove all existing bars
  for l:bar_winid in s:bar_winids
    " The floating windows may have been closed (e.g., :only/<ctrl-w>o).
    if getwininfo(l:bar_winid) ==# []
      continue
    endif
    noautocmd call nvim_win_close(l:bar_winid, 1)
  endfor
  let s:bar_winids = []
endfunction

function! scrollview#RefreshBars() abort
  " Use a try block, so that unanticipated errors don't interfere. The worst
  " case scenario is that bars won't be shown properly, which was deemed
  " preferable to an obscure error message that can be interrupting.
  try
    " Some functionality, like nvim_win_close, cannot be used from the command
    " line window.
    if s:InCommandLineWindow()
      return
    endif
    call scrollview#RemoveBars()
    let l:target_wins = []
    let l:current_only =
          \ s:GetVariable('scrollview_current_only', winnr(), 'tg')
    if l:current_only
      call add(l:target_wins, winnr())
    else
      for l:winid in range(1, winnr('$'))
        if s:IsOrdinaryWindow(l:winid)
          call add(l:target_wins, l:winid)
        endif
      endfor
    endif
    for l:winnr in l:target_wins
      call s:ShowScrollbar(l:winnr)
    endfor
    " Redraw to prevent flickering (which occurred when there were folds, but
    " not otherwise).
    redraw
  catch
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
