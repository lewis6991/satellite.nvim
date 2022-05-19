local api = vim.api

local util = require'satellite.util'

---@type Handler
local handler = {
  name = 'gitsigns',
}
local highlights = {
  add = 'GitSignsAddSV',
  change = 'GitSignsChangeSV',
  delete = 'GitSignsDeleteSV',
}

function handler.init()
  local group = api.nvim_create_augroup('satellite_gitsigns', {})
  vim.api.nvim_set_hl(0, 'GitSignsAddSV', { link = 'GitSignsAdd', default = true })
  vim.api.nvim_set_hl(0, 'GitSignsChangeSV', { link = 'GitSignsDelete', default = true })
  vim.api.nvim_set_hl(0, 'GitSignsChangeSV', { link = 'GitSignsChange', default = true })

  api.nvim_create_autocmd('User', {
    pattern = 'GitsignsHunkUpdate',
    group = group,
    callback = function()
      require('satellite').refresh_bars()
    end
  })
end

function handler.update(bufnr, winid)
  if not package.loaded.gitsigns then
    return {}
  end

  local marks = {}

  local hunks = require'gitsigns'.get_hunks(bufnr)
  for _, hunk in ipairs(hunks or {}) do
    for i = hunk.added.start, hunk.added.start+ math.max(0, hunk.added.count - 1) do
      local hl = highlights[hunk.type]
      local lnum = math.max(1, i)
      local pos = util.row_to_barpos(winid, lnum-1)

      marks[pos] = {
        symbol = hunk.type == 'delete' and '-' or '│',
        highlight = hl
      }
    end
  end

  local ret = {}

  for pos, mark in pairs(marks) do
    ret[#ret+1] = {
      pos = pos,
      highlight = mark.highlight,
      symbol = mark.symbol,
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
