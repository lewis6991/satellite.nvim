local api = vim.api
local fn = vim.fn

local util = require 'satellite.util'
local async = require 'satellite.async'

require 'satellite.autocmd.search'

---@class CacheElem
---@field changedtick integer
---@field pattern string
---@field matches integer[]

---@type table<integer, CacheElem>
local cache = {}

local function is_search_mode()
  if
    vim.o.incsearch
    and vim.o.hlsearch
    and api.nvim_get_mode().mode == 'c'
    and vim.tbl_contains({ '/', '?' }, fn.getcmdtype())
  then
    return true
  end
  return false
end

---@param pattern string
---@return string
local function smartcaseify(pattern)
  if pattern and vim.o.ignorecase and vim.o.smartcase then
    -- match() does not use 'smartcase' so we must handle it
    local smartcase = pattern:find('[A-Z]') ~= nil
    if smartcase and not vim.startswith(pattern, '\\C') then
      return '\\C' .. pattern
    end
  end
  return pattern
end

local function get_pattern()
  if is_search_mode() then
    return vim.fn.getcmdline()
  else
    ---@diagnostic disable-next-line: missing-parameter
    return vim.v.hlsearch == 1 and fn.getreg('/') or ''
  end
end

---@param bufnr integer
---@param pattern? string
---@return integer[]
local function update_matches(bufnr, pattern)
  pattern = pattern or get_pattern()
  pattern = smartcaseify(pattern)

  if
    cache[bufnr]
    and cache[bufnr].changedtick == vim.b[bufnr].changedtick
    and (not pattern or cache[bufnr].pattern == pattern)
  then
    return cache[bufnr].matches
  end

  local matches = {} ---@type integer[]

  if pattern and pattern ~= '' then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)

    local start_time = vim.loop.now()
    for lnum, line in ipairs(lines) do
      local count = 1
      repeat
        local ok, col = pcall(fn.match, line, pattern, 0, count)
        if not ok then
          -- Make sure no lines match any error-causing regex pattern.
          matches = {}
          break
        elseif col ~= -1 then
          matches[#matches + 1] = lnum
        end
        count = count + 1
      until col == -1

      start_time = async.event_control(start_time)
    end
  end

  cache[bufnr] = {
    pattern = pattern,
    changedtick = vim.b[bufnr].changedtick,
    matches = matches,
  }

  return matches
end

--- @param update fun(winid?: integer)
local refresh = async.void(function(update)
  update_matches(api.nvim_get_current_buf())
  update(api.nvim_get_current_win())
end)

---@type Handler
local handler = {
  name = 'search',
}

local function setup_hl()
  api.nvim_set_hl(0, 'SearchSV', {
    default = true,
    fg = api.nvim_get_hl_by_name('Search', true).background,
  })
end

function handler.setup(_config, update)
  local group = api.nvim_create_augroup('satellite_search', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'Search',
    callback = vim.schedule_wrap(function()
      refresh(update)
    end),
  })
end

local SYMBOLS = { '⠂', '⠅', '⠇', '⠗', '⠟', '⠿' }

---@class SearchMark
---@field count integer
---@field highlight string
---@field unique boolean
---@field symbol string

function handler.update(bufnr, winid)
  local marks = {} ---@type SearchMark[]
  local matches = update_matches(bufnr)
  local cursor_lnum = api.nvim_win_get_cursor(0)[1]
  local start_time = vim.loop.now()
  for _, lnum in ipairs(matches) do
    local pos = util.row_to_barpos(winid, lnum - 1)

    local count = 1
    if marks[pos] and marks[pos].count then
      count = marks[pos].count + 1
    end

    if lnum == cursor_lnum then
      marks[pos] = {
        count = count,
        highlight = 'SearchCurrent',
        unique = true,
      }
    elseif count < 6 then
      marks[pos] = {
        count = count,
      }
    end
    start_time = async.event_control(start_time)
  end

  local ret = {} ---@type SatelliteMark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      unique = mark.unique,
      highlight = mark.highlight or 'SearchSV',
      symbol = mark.symbol or SYMBOLS[mark.count] or SYMBOLS[#SYMBOLS],
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
