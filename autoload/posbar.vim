" *************************************************
" * Globals
" *************************************************

" s:bar_winids has the winids of existing bars. An existing value is loaded so
" existing bars can be properly closed when re-sourcing this file.
let s:bar_winids = get(s:, 'bar_winids', [])

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
  let l:topline = l:wininfo['topline']
  " WARN: l:wininfo['botline'] is not properly updated for some movements
  " (Issue #13510). To work around this, `l:topline + l:wininfo['height'] - 1`
  " is used instead. This would not be necessary if the code was always being
  " called in an asynchronous context, as l:wininfo['botline'] would have the
  " correct values by time this code is executed.
  let l:botline = l:topline + l:wininfo['height'] - 1
  let l:line_count = nvim_buf_line_count(l:bufnr)
  let [l:row, l:col] = win_screenpos(l:winnr)
  let l:winheight = winheight(l:winnr)
  " Don't show the position bar when it would span the entire screen.
  if l:winheight >=# l:line_count
    return
  endif
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

function! s:ShowBars(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
  let l:bufnr = winbufnr(l:winnr)
  let l:buf_filetype = getbufvar(l:bufnr, '&l:filetype', '')
  " Skip if the filetype is on the list of exclusions.
  if s:Contains(g:posbar_excluded_filetypes, l:buf_filetype)
    return
  endif
  " Don't show in terminal mode, since the bar won't be properly updated for
  " insertions.
  if getwininfo(l:winid)[0].terminal
    return
  endif
  if winheight(l:winnr) ==# 0 || winwidth(l:winnr) ==# 0
    return
  endif
  let l:bar_position = s:CalculatePosition(l:winnr)
  " TODO: reuse buffers
  let l:buf = nvim_create_buf(0, 1)
  let l:options = {
        \   'relative': 'editor',
        \   'focusable': 0,
        \   'style': 'minimal',
        \   'height': l:bar_position.height,
        \   'width': 1,
        \   'row': l:bar_position.row,
        \   'col': l:bar_position.col
        \ }
  let l:bar_winid = nvim_open_win(l:buf, 0, l:options)
  call add(s:bar_winids, l:bar_winid)
  call setwinvar(l:bar_winid, '&winhighlight', 'Normal:Posbar')
  call nvim_win_set_option(l:bar_winid, 'winblend', g:posbar_winblend)
endfunction

function! posbar#RemoveBars() abort
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

function! posbar#RefreshBars() abort
  " Use a try block, so that unanticipated errors don't interfere. The worst
  " case scenario is that bars won't be shown properly, which was deemed
  " preferable to an obscure error message that can be interrupting.
  try
    " Some functionality, like nvim_win_close, cannot be used from the command
    " line window.
    if s:InCommandLineWindow()
      return
    endif
    call posbar#RemoveBars()
    let l:target_wins = []
    if g:posbar_active_only
      call add(l:target_wins, winnr())
    else
      for l:winid in range(1, winnr('$'))
        if s:IsOrdinaryWindow(l:winid)
          call add(l:target_wins, l:winid)
        endif
      endfor
    endif
    for l:winnr in l:target_wins
      let l:bufnr = winbufnr(l:winnr)
      let l:buftype = nvim_buf_get_option(l:bufnr, 'buftype')
      let l:bufname = bufname(l:bufnr)
      call s:ShowBars(l:winnr)
    endfor
  catch
  endtry
endfunction

" This function refreshes the bars asynchronously. This works better than
" updating synchronously in various scenarios where updating occurs in an
" intermediate state of the editor (e.g., when closing a command-line window),
" which can result in bars being placed where they shouldn't be.
" WARN: For debugging, it's helpful to use synchronous refreshing, so that
" e.g., echom works as expected.
function! posbar#RefreshBarsAsync() abort
  let Callback = {timer_id -> execute('call posbar#RefreshBars()')}
  call timer_start(0, Callback)
endfunction

