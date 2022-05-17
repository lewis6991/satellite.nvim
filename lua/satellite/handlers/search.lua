local api = vim.api
local fn = vim.fn

local util = require'satellite.util'

---@class CacheElem
---@field changedtick integer
---@field pattern string
---@field matches integer[]

---@type table<integer, CacheElem>
local cache = {}

local function is_search_mode()
  if vim.o.incsearch
    and vim.o.hlsearch
    and api.nvim_get_mode().mode == 'c'
    and vim.tbl_contains({ '/', '?' }, fn.getcmdtype()) then
    return true
  end
  return false
end

local MAX_THRESHOLD1 = 500
local MAX_THRESHOLD2 = 1000

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

      local count = 1
      repeat
        local col = fn.match(line, pattern, 0, count)
        if col ~= -1 then
          matches[#matches+1] = lnum
        end
        local max_count = #matches < MAX_THRESHOLD1 and 6 or 1
        if count > max_count then
          break
        end
        count = count + 1
      until col == -1
      if #matches > MAX_THRESHOLD2 then
        break
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

local function refresh()
  if is_search_mode() then
    update_matches(api.nvim_get_current_buf(), fn.getcmdline())
    require('satellite').refresh_bars()
  end
end

-- Clear matches and refresh when :nohl is run
local function on_cmd(cmd, group, f)
  api.nvim_create_autocmd({'CmdlineLeave'}, {
    group = group,
    callback = function()
      if fn.getcmdtype() == ':'
        and vim.startswith(fn.getcmdline(), cmd) then
        f()
      end
    end
  })
end

---@type Handler
local handler = {
  name = 'search'
}

function handler.init()
    api.nvim_set_hl(0, 'SearchSV', {
      fg = api.nvim_get_hl_by_name('Search', true).background
    })

    local group = api.nvim_create_augroup('satellite_search', {})

    api.nvim_create_autocmd('CmdlineChanged', {
      group = group,
      -- Debounce as this is triggered very often
      callback = util.debounce_trailing(refresh)
    })

    api.nvim_create_autocmd({'CmdlineEnter', 'CmdlineLeave'}, {
      group = group,
      callback = refresh
    })

  on_cmd('nohl', group, function()
    update_matches(api.nvim_get_current_buf(), '')
    require('satellite').refresh_bars()
  end)

  -- Refresh when activating search nav mappings
  for _, seq in ipairs{'n', 'N', '&', '*'} do
    vim.keymap.set('n', seq, function()
      vim.schedule(function()
        ---@diagnostic disable-next-line: missing-parameter
        local pattern = vim.v.hlsearch == 1 and fn.getreg('/') or ''
        update_matches(api.nvim_get_current_buf(), pattern)
        require('satellite').refresh_bars()
      end)
      return seq
    end, {expr = true})
  end
end

function handler.update(bufnr)
  local marks = {}
  local matches = update_matches(bufnr)
  local cursor_lnum = api.nvim_win_get_cursor(0)[1]
  for _, lnum in ipairs(matches) do
    marks[#marks+1] = {
      lnum = lnum,
      -- symbol = {'-', '=', '≡'},
      symbol = {'⠂', '⠅', '⠇', '⠗', '⠟', '⠿'},
      highlight = 'SearchSV',
    }
    if lnum == cursor_lnum then
      marks[#marks+1] = {
        lnum      = lnum,
        symbol    = ' ',
        highlight = 'SearchCurrent',
        unique    = true,
      }
    end
  end
  return marks
end

return handler
