" TODO: delete the following line, which is for testing bar transparency
" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
" TODO: option for showing just in the current window or in all windows (for
" the current tab)
" TODO: maybe ways to enable/disable (e.g., minlines, maxlines). maybe leave
" this up to the user with some kind of b: setting.

" TODO: also have to check for the relevant functionality
if !has('nvim')
  finish
endif

" Returns window count, with special handling to exclude floating and external
" windows in neovim. The windows with numbers less than or equal to the value
" returned are assumed non-floating and non-external windows. The
" documentation for ":h CTRL-W_w" says "windows are numbered from top-left to
" bottom-right", which does not ensure this, but checks revealed that floating
" windows are numbered higher than ordinary windows, regardless of position.
function! s:WindowCount() abort
  let l:win_count = 0
  for l:winid in range(1, winnr('$'))
    let l:config = nvim_win_get_config(win_getid(l:winid))
    if !get(l:config, 'external', 0) && get(l:config, 'relative', '') ==# ''
      let l:win_count += 1
    endif
  endfor
  return l:win_count
endfunction

function! s:IsCommandLineWindow(winnr) abort
  let l:bufnr = winbufnr(a:winnr)
  let l:buftype = nvim_buf_get_option(l:bufnr, 'buftype')
  let l:bufname = bufname(l:bufnr)
  return l:buftype ==# 'nofile' && l:bufname ==# '[Command Line]'
endfunction

let s:bar_winids = []

function! s:ShowBars(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
  let l:bufnr = winbufnr(l:winnr)
  let l:wininfo = getwininfo(l:winid)[0]
  " Don't show in terminal mode, since the bar won't be properly updated for
  " insertions.
  if l:wininfo['terminal']
    return
  endif
  let l:topline = l:wininfo['topline']
  " WARN: l:wininfo['botline'] is not properly updated for some movements
  " (Issue #13510). To work around this, `l:topline + l:wininfo['height'] - 1`
  " can alternatively be used. However this is not necessary, since refreshing
  " is called asynchronously, resulting in l:wininfo['botline'] having the
  " correct value when this code runs.
  let l:botline = l:wininfo['botline']
  let l:line_count = nvim_buf_line_count(l:bufnr)

  let [l:row, l:col] = win_screenpos(l:winnr)
  let l:winheight = winheight(l:winnr)
  let l:winwidth = winwidth(l:winnr)
  if l:winheight ==# 0 || l:winwidth ==# 0
    return
  endif
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

  " TODO: reuse buffers
  let l:buf = nvim_create_buf(0, 1)
  
  let l:options = {
        \   'relative': 'editor',
        \   'focusable': 0,
        \   'style': 'minimal',
        \   'height': l:height,
        \   'width': 1,
        \   'row': l:line - 1,
        \   'col': l:col - 1
        \ }
  let l:bar_winid = nvim_open_win(l:buf, 0, l:options)
  call add(s:bar_winids, l:bar_winid)
  " TODO: Highlight color should be user-configurable.
  let l:highlight = 'Visual'
  call setwinvar(l:bar_winid, '&winhighlight', 'Normal:' . l:highlight)
  " Using a winblend of 100 results in the bar becoming invisible on nvim-qt.
  " TODO: make winblend level user-configurable.
  call nvim_win_set_option(l:bar_winid, 'winblend', 50)
endfunction

function! s:RemoveBars() abort
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

" TODO: move this into RefreshBarsAsync, since some of the underlying
" functionality depends on being called asynchronously.
function! s:RefreshBarsSync() abort
  try
    let l:win_count = s:WindowCount()
    " Some functionality, like nvim_win_close, cannot be used from the command
    " line window.
    if s:IsCommandLineWindow(winnr())
      return
    endif
    call s:RemoveBars()
    for l:winnr in range(1, l:win_count)
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
" intermediate state of the editor (when opening a command-line window),
" resulting in bars being placed where they shouldn't be.
" WARN: For debugging, it's helpful to use synchronous refreshing, so that
" e.g., echom works as expected.
function! s:RefreshBarsAsync() abort
  let Callback = {timer_id -> execute('call s:RefreshBarsSync()')}
  call timer_start(0, Callback)
endfunction

" TODO: use some combo of WinLeave/WinEnter to remove scroll bars so that
" they don't overlap with the command line window.

augroup scrollbar
  autocmd!
  autocmd WinScrolled * :call s:RefreshBarsAsync()
  " This handles the case where text is pasted. TextChangedI is not necessary
  " WinScrolled will be triggered if there is scrolling.
  autocmd TextChanged * :call s:RefreshBarsAsync()
  " The following prevents the scrollbar from disappearing when <ctrl-w>o is
  " pressed when there is only one window. A side-effect is that the Nvim
  " warning message, 'Already only one window', which would otherwise be
  " displayed (when there are no bars), is not shown.
  autocmd WinClosed * :call s:RefreshBarsAsync()
  " The following handles when :e is used to load a file.
  autocmd BufWinEnter * :call s:RefreshBarsAsync()
  " The following is used so that bars are shown when cycling through tabs.
  autocmd TabEnter * :call s:RefreshBarsAsync()
augroup END
command Refresh :call s:RefreshBarsAsync()
