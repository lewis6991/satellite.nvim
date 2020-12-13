" *************************************************
" * Preamble
" *************************************************

if get(g:, 'loaded_posbar', 0)
  finish
endif
let g:loaded_posbar = 1

let s:save_cpo = &cpo
set cpo&vim

" The additional check for ##WinScrolled may be redundant, but was added in
" case early versions of nvim 0.5 didn't have that event.
if !has('nvim-0.5') || !exists('##WinScrolled')
  " Logging error with echomsg or echoerr interrupts Neovim's startup by
  " blocking. Fail silently.
  finish
endif

" *************************************************
" * User Configuration
" *************************************************

let g:posbar_on_startup = get(g:, 'posbar_on_startup', 1)
let g:posbar_excluded_filetypes = get(g:, 'posbar_excluded_filetypes', [])
let g:posbar_active_only = get(g:, 'posbar_active_only', 0)
" The default highlight group is specified below.
" Change this default by defining or linking an alternative highlight group.
" E.g., the following will use the Pmenu highlight.
"   :highlight link Posbar Pmenu
" E.g., the following will use custom highlight colors.
"   :highlight Posbar ctermbg=159 guibg=LightCyan
highlight default link Posbar Visual
" Using a winblend of 100 results in the bar becoming invisible on nvim-qt.
let g:posbar_winblend = get(g:, 'posbar_winblend', 50)

" *************************************************
" * Commands
" *************************************************

if !exists(':PosbarRefresh')
  command PosbarRefresh :call s:PosbarRefresh()
endif

if !exists(':PosbarEnable')
  command PosbarEnable :call s:PosbarEnable()
endif

if !exists(':PosbarDisable')
  command PosbarDisable :call s:PosbarDisable()
endif

" *************************************************
" * Core
" *************************************************

" Internal flag for tracking posbar state.
let s:posbar_enabled = g:posbar_on_startup

function! s:PosbarEnable() abort
  let s:posbar_enabled = 1
  augroup posbar
    autocmd!
    " Removing bars when leaving windows was added specifically to accommodate
    " entering the command line window. For the duration of command-line window
    " usage, there will be no bars. Without this, bars can possibly overlap the
    " command line window. This can be problematic particularly when there is a
    " vertical split with the left window's bar on the bottom of the screen,
    " where it would overlap with the center of the command line window.
    autocmd WinLeave * :call posbar#RemoveBars()
    " The following handles bar refreshing when changing the active window,
    " which was required after the WinLeave handling added above.
    autocmd WinEnter,TermEnter * :call posbar#RefreshBars()
    " The following restores bars after leaving the command-line window.
    " Refreshing must be asynchonous, since the command line window is still in
    " an intermediate state when the CmdwinLeave event is triggered.
    autocmd CmdwinLeave * :call posbar#RefreshBarsAsync()
    " The following handles scrolling events, which could arise from various
    " actions, including resizing windows, movements (e.g., j, k), or scrolling
    " (e.g., <ctrl-e>, zz).
    autocmd WinScrolled * :call posbar#RefreshBars()
    " The following handles the case where text is pasted. TextChangedI is not
    " necessary since WinScrolled will be triggered if there is corresponding
    " scrolling.
    autocmd TextChanged * :call posbar#RefreshBars()
    " The following handles when :e is used to load a file.
    autocmd BufWinEnter * :call posbar#RefreshBars()
    " The following is used so that bars are shown when cycling through tabs.
    autocmd TabEnter * :call posbar#RefreshBars()
    " The following error can arise when the last window in a tab is going to be
    " closed, but there are still open floating windows, and at least one other
    " tab.
    "   > "E5601: Cannot close window, only floating window would remain"
    " Neovim Issue #11440 is open to address this. As of 2020/12/12, this issue
    " is a 0.6 milestone.
    " The autocmd below removes bars subsequent to :quit, :wq, or :qall (and
    " also ZZ and ZQ), to avoid the error. However, the error will still arise
    " when <ctrl-w>c or :close are used. To avoid the error in those cases,
    " <ctrl-w>o can be used to first close the floating windows, or
    " alternatively :tabclose can be used (or one of the alternatives handled
    " with the autocmd, like ZQ).
    autocmd QuitPre * :call posbar#RemoveBars()
    autocmd VimResized * :call posbar#RefreshBars()
  augroup END
  call posbar#RefreshBars()
endfunction

function! s:PosbarDisable() abort
  let s:posbar_enabled = 0
  augroup posbar
    autocmd!
  augroup END
  call posbar#RemoveBars()
endfunction

function! s:PosbarRefresh() abort
  if s:posbar_enabled
    call posbar#RefreshBars()
  else
    call posbar#RemoveBars()
  endif
endfunction

if s:posbar_enabled
  call s:PosbarEnable()
endif

" *************************************************
" * Postamble
" *************************************************

let &cpo = s:save_cpo
unlet s:save_cpo
