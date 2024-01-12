local api = vim.api

local util = require 'satellite.util'
local async = require 'satellite.async'

--- @type Satellite.Handler
local handler = {
  name = 'gitsigns',
}

--- @class Satellite.Handlers.GitsignsConfig: Satellite.Handlers.BaseConfig
--- @field signs table<string, string>
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

  local marks = {} --- @type Satellite.Mark[]

  --- @type {type:string, added:{start: integer, count: integer}}[]
  local hunks = require('gitsigns').get_hunks(bufnr)

  local pred = async.winbuf_pred(bufnr, winid)

  for _, hunk in async.ipairs(hunks or {}, pred) do
    local hl = hunk.type == 'add' and 'SatelliteGitSignsAdd'
      or hunk.type == 'delete' and 'SatelliteGitSignsDelete'
      or 'SatelliteGitSignsChange'

    local symbol = config.signs[hunk.type]
    if not symbol or type(symbol) ~= 'string' then
      symbol = hunk.type == 'delete' and '-' or '│'
    end

    local min_lnum = math.max(1, hunk.added.start)
    local min_pos = util.row_to_barpos(winid, min_lnum - 1)

    local max_lnum = math.max(1, hunk.added.start + math.max(0, hunk.added.count - 1))
    local max_pos = util.row_to_barpos(winid, max_lnum - 1)

    for pos = min_pos, max_pos do
      marks[#marks+1] = {
        pos = pos,
        symbol = symbol,
        highlight = hl,
      }
    end
  end

  return marks
end

require('satellite.handlers').register(handler)
