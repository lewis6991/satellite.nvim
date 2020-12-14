" *************************************************
" * Globals
" *************************************************

" s:bar_winids has the winids of existing bars. An existing value is loaded so
" existing bars can be properly closed when re-sourcing this file.
let s:bar_winids = get(s:, 'bar_winids', [])
" s:bar_bufnr has the bufnr of the first buffer created for a position bar.
" Since there is no text displayed in the buffer, the same buffer can be used
" for multiple floating windows. This also prevents the buffer list from
" getting
" high from usage of the plugin.
let s:bar_bufnr = get(s:, 'bar_bufnr', -1)

" *************************************************
" * Utils
" *************************************************

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
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
  let l:col += winwidth(l:winnr) - 1
  let l:line = l:row + l:top
  let l:result = {
        \   'height': l:height,
        \   'row': l:line - 1,
        \   'col': l:col - 1
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
  if s:Contains(g:scrollview_excluded_filetypes, l:buf_filetype)
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
  " Don't show the position bar when it would span the entire screen.
  if l:winheight >=# nvim_buf_line_count(l:bufnr)
    return
  endif
  let l:bar_position = s:CalculatePosition(l:winnr)
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
        \   'row': l:bar_position.row,
        \   'col': l:bar_position.col
        \ }
  let l:bar_winid = nvim_open_win(s:bar_bufnr, 0, l:options)
  call add(s:bar_winids, l:bar_winid)
  " It's not sufficient to just specify Normal highlighting. With just that, a
  " color scheme's specification of EndOfBuffer would be used to color the
  " bottom of the scrollbar.
  let l:winheighlight = 'Normal:ScrollView,EndOfBuffer:ScrollView'
  call setwinvar(l:bar_winid, '&winhighlight', l:winheighlight)
  call setwinvar(l:bar_winid, '&winblend', g:scrollview_winblend)
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
    if g:scrollview_active_only
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

let s:pending_async_refresh_count = 0

function! s:RefreshBarsAsyncCallback(timer_id)
  let s:pending_async_refresh_count -= 1
"  if s:pending_async_refresh_count ># 0
"    " If there are asynchronous refreshes that will occur subsequently, don't
"    " execute this one.
"    return
"  endif
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
