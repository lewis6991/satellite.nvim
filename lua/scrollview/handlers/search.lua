local api = vim.api
local fn = vim.fn

---@class CacheElem
---@field changedtick integer
---@field pattern string
---@field matches integer[]

---@type table<integer, CacheElem>
local cache = {}

local function debounce_trailing(f, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local argv = {...}
    timer:start(ms or 100, 0, function()
      vim.schedule(function()
        timer:stop()
        f(unpack(argv))
      end)
    end)
  end
end

local function is_search_mode()
  if vim.o.incsearch
    and vim.o.hlsearch
    and api.nvim_get_mode().mode == 'c'
    and vim.tbl_contains({ '/', '?' }, fn.getcmdtype()) then
    return true
  end
  return false
end

---@param bufnr integer
---@param pattern? string
---@return integer[]
local function update_matches(bufnr, pattern)
  if cache[bufnr]
    and cache[bufnr].changedtick == vim.b[bufnr].changedtick
    and (not pattern or cache[bufnr].pattern == pattern) then
    return cache[bufnr].matches
  end

  local matches = {}

  if pattern and pattern ~= '' then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)

    for lnum, line in ipairs(lines) do
      local col = fn.match(line, pattern)
      if col ~= -1 then
        matches[#matches+1] = lnum
      end
    end
  end

  cache[bufnr] = {
    pattern = pattern,
    changedtick = vim.b[bufnr].changedtick,
    matches = matches
  }

  return matches
end

local function update()
  if is_search_mode() then
    update_matches(api.nvim_get_current_buf(), fn.getcmdline())
    require('scrollview').refresh_bars()
  end
end

api.nvim_set_hl(0, 'SearchSV', {
  fg = api.nvim_get_hl_by_name('Search', true).background
})

local group = api.nvim_create_augroup('scrollview_search', {})

api.nvim_create_autocmd('CmdlineChanged', {
  group = group,
  -- Debounce as this is triggered very often
  callback = debounce_trailing(update)
})

api.nvim_create_autocmd({'CmdlineEnter', 'CmdlineLeave'}, {
  group = group,
  callback = update
})

-- Clear matches and refresh when :nohl is run
api.nvim_create_autocmd({'CmdlineLeave'}, {
  group = group,
  callback = function()
    if fn.getcmdtype() == ':'
        and vim.startswith(fn.getcmdline(), 'nohl') then
      update_matches(api.nvim_get_current_buf(), '')
      require('scrollview').refresh_bars()
    end
  end
})

-- Refresh when activating search nav mappings
for _, seq in ipairs{'n', 'N', '&', '*'} do
  vim.keymap.set('n', seq, function()
    vim.schedule(function()
      local pattern = vim.v.hlsearch == 1 and fn.getreg('/') or ''
      update_matches(api.nvim_get_current_buf(), pattern)
      require('scrollview').refresh_bars()
    end)
    return seq
  end, {expr = true})
end

require('scrollview.handlers').register('search', function(bufnr)
  local marks = {}
  local matches = update_matches(bufnr)
  local cursor_lnum = api.nvim_win_get_cursor(0)[1]
  for _, lnum in ipairs(matches) do
    marks[#marks+1] = {
      lnum = lnum,
      symbol = '─',
      highlight = lnum == cursor_lnum and 'SearchCurrent' or 'SearchSV'
    }
  end
  return marks
end)
