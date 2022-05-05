local api = vim.api

---@class CacheElem
---@field changedtick integer
---@field pattern string
---@field matches integer[]

---@type table<integer, CacheElem>
local cache = {}

local function debounce_trailing(fn, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local argv = {...}
    timer:start(ms or 100, 0, function()
      vim.schedule(function()
        timer:stop()
        fn(unpack(argv))
      end)
    end)
  end
end

local function is_search_mode()
  if vim.o.incsearch
    and api.nvim_get_mode().mode == 'c'
    and vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype()) then
    return true
  end
  return false
end

local function getmatches(bufnr)
  local pattern = is_search_mode() and vim.fn.getcmdline() or vim.fn.getreg('/')

  if not pattern or pattern == '' then
    return {}
  end

  if cache[bufnr]
    and cache[bufnr].changedtick == vim.b[bufnr].changedtick
    and cache[bufnr].pattern == pattern then
    return cache[bufnr].matches
  end

  local matches = {}

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)

  for lnum, line in ipairs(lines) do
    local col = vim.fn.match(line, pattern)
    if col ~= -1 then
      matches[#matches+1] = lnum
    end
  end

  cache[bufnr] = {
    pattern = pattern,
    changedtick = vim.b[bufnr].changedtick,
    matches = matches
  }

  return matches
end

api.nvim_set_hl(0, 'SearchSV', {
  fg = api.nvim_get_hl_by_name('Search', true).background
})

local function update()
  if is_search_mode() then
    require('scrollview').refresh_bars()
  end
end

local group = api.nvim_create_augroup('scrollview_search', {})

api.nvim_create_autocmd('CmdlineChanged', {
  group = group,
  callback = debounce_trailing(update)
})

api.nvim_create_autocmd({'CmdlineEnter', 'CmdlineLeave'}, {
  group = group,
  callback = update
})

for _, seq in ipairs{'n', 'N', '&', '*'} do
  vim.keymap.set('n', seq, function()
    vim.schedule(require('scrollview').refresh_bars)
    return seq
  end, {expr = true})
end

require('scrollview.handlers').register('diagnostics', function(bufnr)
  local marks = {}
  local matches = getmatches(bufnr)
  local cursor_lnum = api.nvim_win_get_cursor(0)[1]
  for _, lnum in ipairs(matches) do
    marks[#marks+1] = {
      lnum = lnum,
      symbol = '-',
      highlight = lnum == cursor_lnum and 'SearchCurrent' or 'SearchSV'
    }
  end
  return marks
end)
