local api = vim.api

local util = require('satellite.util')

local HIGHLIGHT = 'SatelliteCursor'

---@type Handler
local handler = {
  name = 'cursor',
}

---@class CursorConfig: HandlerConfig
---@field symbols string[]
local config = {
  enable = true,
  overlap = true,
  priority = 100,
  symbols = { '⎺', '⎻', '⎼', '⎽' }
}

local function setup_hl()
  api.nvim_set_hl(0, HIGHLIGHT, {
    default = true,
    fg = api.nvim_get_hl(0, { name = 'NonText' }).fg,
  })
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  local group = vim.api.nvim_create_augroup('satellite_cursor', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI' }, {
    group = group,
    callback = update
  })
end

--- @param symbols string[]
--- @param f number
--- @return string
local function get_symbol(symbols, f)
  local total = #symbols
  local index = math.max(1, util.round((0.5 - f) * total))
  return symbols[index] or tostring(index)
end

function handler.update(_, winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)

  local pos, f = util.row_to_barpos(winid, cursor[1] - 1)

  return {{
    pos = pos,
    highlight = HIGHLIGHT,
    symbol = get_symbol(config.symbols, f)
  }}
end

require('satellite.handlers').register(handler)
