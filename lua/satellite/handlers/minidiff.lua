local util = require('satellite.util')
local async = require('satellite.async')

--- @type Satellite.Handler
local handler = {
  name = 'minidiff',
}

--- @class Satellite.Handlers.MiniDiffConfig: Satellite.Handlers.BaseConfig
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
  for _, sfx in ipairs({ 'Add', 'Change', 'Delete' }) do
    local target = 'MiniDiffSign' .. sfx
    if pcall(vim.api.nvim_get_hl_id_by_name, target) then
      vim.api.nvim_set_hl(0, 'SatelliteMiniDiff' .. sfx, {
        default = true,
        link = target,
      })
    end
  end
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  local group = vim.api.nvim_create_augroup('satellite_minidiff', {})

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniDiffUpdated',
    group = group,
    callback = update,
  })
end

function handler.update(bufnr, winid)
  if not package.loaded['mini.diff'] then return {} end

  --- @type Satellite.Mark
  local marks = {}

  local buf_data = require('mini.diff').get_buf_data(bufnr)
  if not buf_data then return {} end

  local pred = async.winbuf_pred(bufnr, winid)

  for _, hunk in async.ipairs(buf_data.hunks or {}, pred) do
    local hl = hunk.type == 'add' and 'SatelliteMiniDiffAdd'
      or hunk.type == 'change' and 'SatelliteMiniDiffChange'
      or 'SatelliteMiniDiffDelete'

    local symbol = config.signs[hunk.type]
    if not symbol or type(symbol) ~= 'string' then symbol = hunk.type == 'delete' and '-' or '│' end

    local min_lnum = math.max(1, hunk.buf_start)
    local min_pos = util.row_to_barpos(winid, min_lnum - 1)

    local max_lnum = math.max(1, hunk.buf_start + math.max(0, hunk.buf_count - 1))
    local max_pos = util.row_to_barpos(winid, max_lnum - 1)

    for pos = min_pos, max_pos do
      marks[#marks + 1] = {
        pos = pos,
        symbol = symbol,
        highlight = hl,
      }
    end
  end

  return marks
end

require('satellite.handlers').register(handler)
