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

" Returns true for ordinary windows (not floating and not external), and
" false otherwise.
function! s:IsOrdinaryWindow(winid) abort
  let l:config = nvim_win_get_config(win_getid(a:winid))
  let l:not_external = !get(l:config, 'external', 0)
  let l:not_floating = get(l:config, 'relative', '') ==# ''
  return l:not_external && l:not_floating
endfunction

" Returns window count, with special handling to exclude floating and external
" windows in neovim. The windows with numbers less than or equal to the value
" returned are assumed non-floating and non-external windows. The
" documentation for ":h CTRL-W_w" says "windows are numbered from top-left to
" bottom-right", which does not ensure this, but checks revealed that floating
" windows are numbered higher than ordinary windows, regardless of position.
function! s:WindowCount() abort
  let l:win_count = 0
  for l:winid in range(1, winnr('$'))
    if s:IsOrdinaryWindow(l:winid)
      let l:win_count += 1
    endif
  endfor
  return l:win_count
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

" s:bar_winids has the winids of existing bars. An existing value is loaded so
" existing bars can be properly closed when re-sourcing this file.
let s:bar_winids = get(s:, 'bar_winids', [])

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
  " is used instead. This would not be necessary if the code was always being
  " called in an asynchronous context, where l:wininfo['botline'] would have
  " the correct values by time this code is executed.
  let l:botline = l:topline + l:wininfo['height'] - 1
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

function! s:RefreshBars() abort
  try
    " Some functionality, like nvim_win_close, cannot be used from the command
    " line window.
    if s:InCommandLineWindow()
      return
    endif
    call s:RemoveBars()
    let l:win_count = s:WindowCount()
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
" intermediate state of the editor (e.g., when closing a command-line window),
" which can result in bars being placed where they shouldn't be.
" WARN: For debugging, it's helpful to use synchronous refreshing, so that
" e.g., echom works as expected.
function! s:RefreshBarsAsync() abort
  let Callback = {timer_id -> execute('call s:RefreshBars()')}
  call timer_start(0, Callback)
endfunction

augroup scrollbar
  autocmd!
  " Removing bars when leaving windows was added specifically to accommodate
  " entering the command line window. For the duration of command-line window
  " usage, there will be no bars. Without this, bars can possibly overlap the
  " command line window. This can be problematic particularly when there is a
  " vertical split with the left window's bar on the bottom of the screen,
  " where it would overlap with the center of the command line window.
  autocmd WinLeave * :call s:RemoveBars()
  " The following handles bar refreshing when changing the active window,
  " which was required after the WinLeave handling added above.
  autocmd WinEnter * :call s:RefreshBars()
  " The following restores bars after leaving the command-line window.
  " Refreshing must be asynchonous, since the command line window is still in
  " an intermediate state when the CmdlineLeave event is triggered.
  autocmd CmdlineLeave * :call s:RefreshBarsAsync()
  " The following handles scrolling events, which could arise from various
  " actions, including resizing windows, movements (e.g., j, k), or scrolling
  " (e.g., <ctrl-e>, zz).
  autocmd WinScrolled * :call s:RefreshBars()
  " The following handles the case where text is pasted. TextChangedI is not
  " necessary since WinScrolled will be triggered if there is corresponding
  " scrolling.
  autocmd TextChanged * :call s:RefreshBars()
  " The following handles when :e is used to load a file.
  autocmd BufWinEnter * :call s:RefreshBars()
  " The following is used so that bars are shown when cycling through tabs.
  autocmd TabEnter * :call s:RefreshBars()
augroup END
