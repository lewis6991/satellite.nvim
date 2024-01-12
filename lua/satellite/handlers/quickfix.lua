local api = vim.api

local util = require('satellite.util')

local HIGHLIGHT = 'SatelliteQuickfix'

--- @type Satellite.Handler
local handler = {
  name = 'quickfix',
}

--- @class Satellite.Handlers.QuickfixConfig: Satellite.Handlers.BaseConfig
--- @field symbols string[]
local config = {
  priority = 60,
  signs = { '-', '=', '≡' },
}

local function setup_hl()
  api.nvim_set_hl(0, HIGHLIGHT, { default = true, link = 'WarningMsg' })
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  local group = vim.api.nvim_create_augroup('satellite_quickfix', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  vim.api.nvim_create_autocmd('QuickFixCmdPost', {
    group = group,
    callback = update,
  })
end

function handler.update(bufnr, winid)
  local marks = {} --- @type {count: integer, severity: integer}[]
  for _, item in ipairs(vim.fn.getqflist()) do
    if item.bufnr == bufnr then
      local pos = util.row_to_barpos(winid, item.lnum)

      local count = 1
      if marks[pos] and marks[pos].count then
        count = marks[pos].count + 1
      end

      marks[pos] = {
        count = count,
      }
    end
  end

  local ret = {} --- @type Satellite.Mark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      highlight = HIGHLIGHT,
      symbol = config.signs[mark.count] or config.signs[#config.signs],
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
