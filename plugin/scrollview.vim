" *************************************************
" * Preamble
" *************************************************

if get(g:, 'loaded_scrollview', 0)
  finish
endif
let g:loaded_scrollview = 1

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

let g:scrollview_on_startup = get(g:, 'scrollview_on_startup', 1)
let g:scrollview_mode = get(g:, 'scrollview_mode', 'simple')
let g:scrollview_excluded_filetypes = 
      \ get(g:, 'scrollview_excluded_filetypes', [])
let g:scrollview_current_only = get(g:, 'scrollview_current_only', 0)
" The default highlight group is specified below.
" Change this default by defining or linking an alternative highlight group.
" E.g., the following will use the Pmenu highlight.
"   :highlight link ScrollView Pmenu
" E.g., the following will use custom highlight colors.
"   :highlight ScrollView ctermbg=159 guibg=LightCyan
highlight default link ScrollView Visual
" Using a winblend of 100 results in the bar becoming invisible on nvim-qt.
let g:scrollview_winblend = get(g:, 'scrollview_winblend', 50)
let g:scrollview_column = get(g:, 'scrollview_column', 1)
let g:scrollview_base = get(g:, 'scrollview_base', 'right')

" *************************************************
" * Commands
" *************************************************

if !exists(':ScrollViewRefresh')
  command -bar ScrollViewRefresh :call s:ScrollViewRefresh()
endif

if !exists(':ScrollViewEnable')
  command -bar ScrollViewEnable :call s:ScrollViewEnable()
endif

if !exists(':ScrollViewDisable')
  command -bar ScrollViewDisable :call s:ScrollViewDisable()
endif

" *************************************************
" * Mappings
" *************************************************

" <plug> mappings for mouse functionality.
" E.g., <plug>(ScrollViewLeftMouse)
let s:mouse_plug_pairs = [
      \   ['ScrollViewLeftMouse',   'left'  ],
      \   ['ScrollViewMiddleMouse', 'middle'],
      \   ['ScrollViewRightMouse',  'right' ],
      \   ['ScrollViewX1Mouse',     'x1'    ],
      \   ['ScrollViewX2Mouse',     'x2'    ],
      \ ]
for [s:plug_name, s:button] in s:mouse_plug_pairs
  let s:lhs = printf('<silent> <plug>(%s)', s:plug_name)
  let s:rhs = printf('<cmd>call scrollview#HandleMouse("%s")<cr>', s:button)
  execute 'noremap ' . s:lhs . ' ' . s:rhs
  execute 'inoremap ' . s:lhs . ' ' . s:rhs
endfor

" Additional <plug> mappings are defined for convenience of creating
" user-defined mappings that call nvim-scrollview functionality. However,
" since the usage of <plug> mappings requires recursive map commands, this
" prevents mappings that both call <plug> functions and have the
" left-hand-side key sequences repeated not at the beginning of the
" right-hand-side (see :help recursive_mapping for details). Experimentation
" suggests <silent> is not necessary for <cmd> mappings, but it's added to
" make it explicit.
noremap <silent> <plug>(ScrollViewDisable) <cmd>ScrollViewDisable<cr>
noremap <silent> <plug>(ScrollViewEnable) <cmd>ScrollViewEnable<cr>
noremap <silent> <plug>(ScrollViewRefresh) <cmd>ScrollViewRefresh<cr>

" *************************************************
" * Core
" *************************************************

" Internal flag for tracking scrollview state.
let s:scrollview_enabled = g:scrollview_on_startup

function! s:ScrollViewEnable() abort
  let s:scrollview_enabled = 1
  augroup scrollview
    autocmd!
    " The following handles bar refreshing when changing the current window.
    " There is code in RefreshBars() that removes the bars when entering the
    " command line window.
    autocmd WinEnter,TermEnter * :call scrollview#RefreshBars()
    " The following restores bars after leaving the command-line window.
    " Refreshing must be asynchonous, since the command line window is still
    " in an intermediate state when the CmdwinLeave event is triggered.
    autocmd CmdwinLeave * :call scrollview#RefreshBarsAsync()
    " The following handles scrolling events, which could arise from various
    " actions, including resizing windows, movements (e.g., j, k), or
    " scrolling (e.g., <ctrl-e>, zz). Refreshing is asynchronous so that
    " 'botline' is correctly calculated where applicable, and so that mouse
    " wheel scrolls are more responsive (since redundant refreshes are
    " dropped).
    autocmd WinScrolled * :call scrollview#RefreshBarsAsync()
    " The following handles the case where text is pasted. TextChangedI is not
    " necessary since WinScrolled will be triggered if there is corresponding
    " scrolling. Refreshing is asynchronous so that 'botline' is correctly
    " calculated where applicable (e.g., dG command, to delete from current
    " line until the end of the document).
    autocmd TextChanged * :call scrollview#RefreshBarsAsync()
    " The following handles when :e is used to load a file. The asynchronous
    " version is used to handle the case where :e is used to reload an
    " existing file, that is already scrolled. This avoids a scenario where
    " the scrollbar is refreshed while the window is an intermediate state,
    " resulting in the scrollbar moving to the top of the window.
    autocmd BufWinEnter * :call scrollview#RefreshBarsAsync()
    " The following is used so that bars are shown when cycling through tabs.
    autocmd TabEnter * :call scrollview#RefreshBars()
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
    autocmd QuitPre * :call scrollview#RemoveBars()
    autocmd VimResized * :call scrollview#RefreshBars()
  augroup END
  " The initial refresh is asynchronous, since :ScrollViewEnable can be used
  " in a context where Neovim is in an intermediate state. For example, for
  " ':bdelete | ScrollViewEnable', with synchronous processing, the 'topline'
  " and 'botline' in getwininfo's results correspond to the existing buffer
  " that :bdelete was called on.
  call scrollview#RefreshBarsAsync()
endfunction

function! s:ScrollViewDisable() abort
  let s:scrollview_enabled = 0
  augroup scrollview
    autocmd!
  augroup END
  call scrollview#RemoveBars()
endfunction

function! s:ScrollViewRefresh() abort
  if s:scrollview_enabled
    call scrollview#RefreshBars()
  else
    call scrollview#RemoveBars()
  endif
endfunction

if s:scrollview_enabled
  " Enable scrollview asynchronously. This avoids an issue that prevents diff
  " mode from functioning properly when it's launched at startup (i.e., with
  " nvim -d). The issue is reported in Neovim Issue #13720.
  call timer_start(0, {-> execute('call s:ScrollViewEnable()')})
endif

" *************************************************
" * Postamble
" *************************************************

let &cpo = s:save_cpo
unlet s:save_cpo
