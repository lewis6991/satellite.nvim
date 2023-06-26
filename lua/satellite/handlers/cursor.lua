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

function handler.update(_, winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)

  local util = require('satellite.util')

  return {{
    pos = util.row_to_barpos(winid, cursor[1] - 1),
    highlight = 'NonText',
    symbol = '-'
  }}
end

require('satellite.handlers').register(handler)
