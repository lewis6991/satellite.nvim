local util = require('satellite.util')

---@type Handler
local handler = {
  name = 'cursor',
}

function handler.setup(_config, update)
  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI' }, {
    group = vim.api.nvim_create_augroup('satellite_cursor', {}),
    callback = update
  })
end

local CURSOR_SYMBOLS = {'⎺', '⎻', '⎼', '⎽' }

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
    highlight = 'NonText',
    symbol = get_symbol(CURSOR_SYMBOLS, f)
  }}
end

require('satellite.handlers').register(handler)
