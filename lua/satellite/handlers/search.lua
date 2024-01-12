local api = vim.api
local fn = vim.fn

local util = require 'satellite.util'
local async = require 'satellite.async'

require 'satellite.autocmd.search'

local HIGHLIGHT = 'SatelliteSearch'
local HIGHLIGHT_CURRENT = 'SatelliteSearchCurrent'

--- @class Satellite.Handlers.SearchConfig: Satellite.Handlers.BaseConfig
local config = {
  enable = true,
  overlap = true,
  priority = 10,
  symbols = { '⠂', '⠅', '⠇', '⠗', '⠟', '⠿' },
}

--- @class Satellite.Handlers.Search.CacheElem
--- @field changedtick integer
--- @field pattern string
--- @field matches integer[]

--- @type table<integer, Satellite.Handlers.Search.CacheElem>
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

--- @param pattern string
--- @return string
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

--- @return string
local function get_pattern()
  if is_search_mode() then
    return vim.fn.getcmdline()
  end
  return vim.v.hlsearch == 1 and fn.getreg('/') --[[@as string]] or ''
end

--- @param bufnr integer
--- @param pattern? string
--- @return table<integer,integer>
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

  local matches = {} --- @type table<integer,integer>

  if pattern and pattern ~= '' then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)

    local pred = async.winbuf_pred(bufnr)

    for lnum, line in async.ipairs(lines, pred) do
      local count = 1
      repeat
        local ok, col = pcall(fn.match, line, pattern, 0, count)
        if not ok then
          -- Make sure no lines match any error-causing regex pattern.
          matches[lnum] = 0
          break
        elseif col ~= -1 then
          matches[lnum] = (matches[lnum] or 0) + 1
        end
        if count >= #config.symbols then
          break
        end
        count = count + 1
      until col == -1
    end
  end

  cache[bufnr] = {
    pattern = pattern,
    changedtick = vim.b[bufnr].changedtick,
    matches = matches,
  }

  return matches
end

--- @param update fun()
local refresh = async.void(function(update)
  update_matches(api.nvim_get_current_buf())
  -- Run update outside of an async context.
  vim.schedule(update)
end)

--- @type Satellite.Handler
local handler = {
  name = 'search',
}

local function setup_hl()
  api.nvim_set_hl(0, HIGHLIGHT, {
    default = true,
    fg = api.nvim_get_hl_by_name('Search', true).background,
  })

  local has_sc, sc_hl = pcall(api.nvim_get_hl_by_name, 'SearchCurrent', true)
  if has_sc then
    api.nvim_set_hl(0, HIGHLIGHT_CURRENT, {
      default = true,
      fg = sc_hl.background,
    })
  end
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

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

--- @class SearchMark
--- @field count integer
--- @field highlight? string
--- @field unique? boolean
--- @field symbol? string

function handler.update(bufnr, winid)
  local marks = {} --- @type SearchMark[]
  local matches = update_matches(bufnr)

  if not api.nvim_buf_is_valid(bufnr) or not api.nvim_win_is_valid(winid) then
    return {}
  end

  local cursor_lnum = api.nvim_win_get_cursor(winid)[1]

  local pred = async.winbuf_pred(bufnr, winid)

  for lnum, count in async.pairs(matches, pred) do
    local pos = util.row_to_barpos(winid, lnum - 1)

    if marks[pos] and marks[pos].count then
      count = count + marks[pos].count
    end

    if lnum == cursor_lnum then
      marks[pos] = {
        count = count,
        highlight = HIGHLIGHT_CURRENT,
        unique = true,
      }
    elseif count <= #config.symbols then
      marks[pos] = {
        count = count,
      }
    end
  end

  local ret = {} --- @type Satellite.Mark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      unique = mark.unique,
      highlight = mark.highlight or HIGHLIGHT,
      symbol = mark.symbol or config.symbols[mark.count] or config.symbols[#config.symbols],
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
