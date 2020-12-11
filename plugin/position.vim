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
  if !has('nvim') || !exists('*nvim_win_get_config')
    return winnr('$')
  endif
  let l:win_count = 0
  for l:winid in range(1, winnr('$'))
    let l:config = nvim_win_get_config(win_getid(l:winid))
    if !get(l:config, 'external', 0) && get(l:config, 'relative', '') ==# ''
      let l:win_count += 1
    endif
  endfor
  return l:win_count
endfunction

let s:bar_winids = []

function! s:ShowBars(winnr) abort
  let l:winnr = a:winnr
  let l:winid = win_getid(l:winnr)
  let l:bufnr = winbufnr(l:winnr)
  let l:wininfo = getwininfo(l:winid)[0]
  let l:topline = l:wininfo['topline']
  " l:wininfo['botline'] is not properly updated for some movements (Issue
  " #13510). Manually calculate botline instead, using l:wininfo['height'].
  let l:botline = l:topline + l:wininfo['height']
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
  " TODO: apply highlighting properly
  call nvim_win_set_option(l:bar_winid, 'winblend', 30)
endfunction

function! s:Toggle() abort
  " TODO: remove all bars
  for l:bar_winid in s:bar_winids
    " The floating windows may have been closed (e.g., :only/<ctrl-w>o).
    if getwininfo(l:bar_winid) ==# []
      continue
    endif
    noautocmd call nvim_win_close(l:bar_winid, 1)
  endfor
  let s:bar_winids = []
  let l:win_count = s:WindowCount()
  for l:winnr in range(1, l:win_count)
    " TODO: don't enable on command line window. probably due to error...
    " It might just be problematic when this gets called from there...
    "if &buftype ==# 'nofile' && bufname('%') ==# '[Command Line]'
    "  return
    "endif
    call s:ShowBars(l:winnr)
  endfor
endfunction

augroup scrollbar
  autocmd!
  autocmd VimEnter * :call s:Toggle()
  autocmd WinScrolled * :call s:Toggle()
  " This handles the case where text is pasted. TextChangedI is not necessary
  " since scrolling will occur.
  autocmd TextChanged * :call s:Toggle()
  "autocmd WinNew * :call s:Toggle()
  " Will need this and maybe WinLeave to handle window closes
  autocmd WinEnter * :call s:Toggle()
  " The following may be needed in some cases. For <ctrl-w>o with one Window
  " remaining, an error is displayed.
  "autocmd WinLeave * :call s:Toggle()
  "autocmd WinClosed * :call s:Toggle()
augroup END
