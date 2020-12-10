" TODO: option for showing just in the current window or in all windows (for
" the current tab)
" TODO: maybe ways to enable/disable (e.g., minlines, maxlines). maybe leave
" this up to the user with some kind of b: setting.

let s:x = 1
"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
function! s:Toggle() abort
  " TODO: Delete
  "echom s:x
  let s:x = s:x + 1
  " TODO: Don't use popup_clear()
  call popup_clear()
  let [l:row, l:col] = win_screenpos(winnr())
  " TODO: line() takes a winid
  let l:winheight = winheight(winnr())
  " Don't show the position bar when it would span the entire screen.
  if l:winheight >=# line('$')
    return
  endif
  " l:top is relative to the active window, and 0-indexed.
  let l:top = 0
  if line('$') ># 1
    let l:top = (line('w0') - 1.0) / (line('$') - 1)
    let l:top = float2nr(round((l:winheight - 1) * l:top))
  endif
  let l:height = l:winheight
  if line('$') ># l:height
    let l:height = (l:winheight - 1.0) / (line('$') - 1)
    let l:height = float2nr(ceil(l:height * l:winheight))
  endif
  " Make sure bar properly reflects bottom of document.
  if line('w$') ==# line('$')
    let l:top = l:winheight - l:height
  endif
  " Make sure bar never overlaps status line.
  if l:top + l:height ># l:winheight
    let l:top = l:winheight - l:height
  endif
  let l:col += winwidth(winnr()) - 1
  let l:line = l:row + l:top

  " TODO: better prep for text (not needed on neovim with invisible windows)
  " TODO: chars will become state for ctrl-e/ctrl-y
  " TODO: maybe make this experimental/optional until Vim has WinScrolled.
  let l:text = ''

  "for l:i in range(l:height)
  "  " A screen redraw is necessary for characters to take their places prior
  "  " to calling screenstring.
  "  redraw
  "  echom screenstring(l:line, l:col)
  "  let l:text .= screenstring(l:line + l:i, l:col)
  "  "let l:text .= getline(l:top + l:i + 1)[l:col]
  "endfor
  
  let l:options = {
        \   'line': l:line,
        \   'col': l:col,
        \   'minheight': l:height,
        \   'maxheight': l:height,
        \   'maxwidth': 1,
        \   'minwidth': 1,
        \   'zindex': 1,
        \   'highlight': 'Pmenu',
        \ }
  let l:winid = popup_create(l:text, l:options)
endfunction

" TODO: maybe intercepting status line updates is the way to go
" TODO: maybe using a timer, combined with a check if updating is necessary,
" is the way to go.

" Doesn't work with ctrl-e/ctrl-y/zz/zt/zb, and also doesn't work with split
" then close (ctrl-v, ctrl-o).
" TODO maybe it makes more sense to do this with a timer
" TODO: Maybe a workaround is to only show this when scrolling...
" This would work around the complications that arise from trying to keep it
" in sync.
augroup scrollbar
  autocmd!
"  "autocmd CursorMoved * :let x = x + 1 | echom x
"  "autocmd CursorMovedI * :let x = x + 1 | echom x
"  " WinScrolled currently only in neovim
"  "autocmd WinScrolled * :call s:Toggle()
"  autocmd TextChanged * :call s:Toggle()
"  "autocmd TextChangedI * :call s:Toggle()
"  " TODO: only use if no WinScrolled. This won't work as well (e.g., won't
"  " support ctrl-e and/or ctrl-y, zb, zt, zz).
"  autocmd CursorMoved * :call s:Toggle()
"  autocmd WinNew * :call s:Toggle()
"  autocmd WinEnter * :call s:Toggle()
"  autocmd WinLeave * :call s:Toggle()
"  autocmd VimResized * :call s:Toggle()
"  "TODO: timer for checking for window resize... there is no event.
augroup END

function! s:Callback(timer)
  call s:Toggle()
endfunction

let s:timer = timer_start(30, function('s:Callback'), {'repeat': -1})

