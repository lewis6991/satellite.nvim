local api = vim.api

local util = require 'satellite.util'

---@type Satellite.Handler
local handler = {
  name = 'gitsigns',
}

---@class Satellite.Handlers.GitsignsConfig: Satellite.Handlers.BaseConfig
---@field signs table<string, string>
local config = {
  enable = true,
  overlap = false,
  priority = 20,
  signs = {
    add = '│',
    change = '│',
    delete = '-',
  },
}

local function setup_hl()
  for _, sfx in ipairs { 'Add', 'Delete', 'Change' } do
    local target = 'GitSigns' .. sfx
    if pcall(api.nvim_get_hl_id_by_name, target) then
      api.nvim_set_hl(0, 'SatelliteGitSigns' .. sfx, {
        default = true,
        link = target,
      })
    end
  end
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  local group = api.nvim_create_augroup('satellite_gitsigns', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  api.nvim_create_autocmd('User', {
    pattern = 'GitSignsUpdate',
    group = group,
    callback = update,
  })
end

function handler.update(bufnr, winid)
  if not package.loaded.gitsigns then
    return {}
  end

  local marks = {} ---@type Satellite.Mark[]

  ---@type {type:string, added:{start: integer, count: integer}}[]
  local hunks = require 'gitsigns'.get_hunks(bufnr)

  for _, hunk in ipairs(hunks or {}) do
    for i = hunk.added.start, hunk.added.start + math.max(0, hunk.added.count - 1) do
      local hl = hunk.type == 'add' and 'SatelliteGitSignsAdd'
        or hunk.type == 'delete' and 'SatelliteGitSignsDelete'
        or 'SatelliteGitSignsChange'
      local lnum = math.max(1, i)
      local pos = util.row_to_barpos(winid, lnum - 1)
      local symbol = config.signs[hunk.type]
      if not symbol or type(symbol) ~= 'string' then
        symbol = hunk.type == 'delete' and '-' or '│'
      end

      marks[pos] = {
        symbol = symbol,
        highlight = hl,
      }
    end
  end

  local ret = {} ---@type Satellite.Mark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      highlight = mark.highlight,
      symbol = mark.symbol,
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
