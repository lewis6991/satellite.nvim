" Test the consistency of linewise and spanwise computations.

" Load a file with many lines.
help eval.txt

let s:lua_module = luaeval('require("scrollview")')

let s:line_count = nvim_buf_line_count(0)

let s:vline_count_spanwise =
      \ s:lua_module.virtual_line_count_spanwise(1, s:line_count)
let s:vline_count_linewise =
      \ s:lua_module.virtual_line_count_linewise(1, s:line_count)
call assert_equal(s:line_count, s:vline_count_spanwise)
call assert_equal(s:vline_count_spanwise, s:vline_count_linewise)
let s:vtopline_lookup_spanwise =
      \ s:lua_module.virtual_topline_lookup_spanwise()
let s:vtopline_lookup_linewise =
      \ s:lua_module.virtual_topline_lookup_linewise()
call assert_equal(s:vtopline_lookup_spanwise, s:vtopline_lookup_linewise)

" Create folds.
set foldmethod=indent
normal! zM

let s:vline_count_spanwise =
      \ s:lua_module.virtual_line_count_spanwise(1, s:line_count)
let s:vline_count_linewise =
      \ s:lua_module.virtual_line_count_linewise(1, s:line_count)
call assert_true(s:vline_count_spanwise <# s:line_count)
call assert_equal(s:vline_count_spanwise, s:vline_count_linewise)
let s:vtopline_lookup_spanwise =
      \ s:lua_module.virtual_topline_lookup_spanwise()
call assert_notequal(s:vtopline_lookup_spanwise, s:vtopline_lookup_linewise)
let s:vtopline_lookup_linewise =
      \ s:lua_module.virtual_topline_lookup_linewise()
call assert_equal(s:vtopline_lookup_spanwise, s:vtopline_lookup_linewise)
