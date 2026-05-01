local api = vim.api

local util = require 'satellite.util'
local async = require 'satellite.async'

--- @class Satellite.Handler.Gitsigns : Satellite.Handler
local handler = {
  name = 'gitsigns',
}

--- @class Satellite.Handlers.GitsignsConfig: Satellite.Handlers.BaseConfig
local config = {
  enable = true,
  overlap = false,
  priority = 20,
  signs = {
    add = '│',
    change = '│',
    delete = '-',
  },
  staged = {
    enable = true,
    signs = {
      add = '│',
      change = '│',
      delete = '-',
    },
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

    local staged_target = 'GitSignsStaged' .. sfx
    local fallback = pcall(api.nvim_get_hl_id_by_name, staged_target) and staged_target
      or 'GitSigns' .. sfx
    if pcall(api.nvim_get_hl_id_by_name, fallback) then
      api.nvim_set_hl(0, 'SatelliteGitSignsStaged' .. sfx, {
        default = true,
        link = fallback,
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

--- @return {type:string, added:{start: integer, count: integer}}[]?
local function get_staged_hunks(bufnr)
  local ok, cache_mod = pcall(require, 'gitsigns.cache')
  if not ok or not cache_mod or not cache_mod.cache then
    return nil
  end
  local entry = cache_mod.cache[bufnr]
  if not entry or not entry.hunks_staged then
    return nil
  end
  local out = {}
  for _, h in ipairs(entry.hunks_staged) do
    out[#out + 1] = { type = h.type, added = h.added }
  end
  return out
end

function handler.update(bufnr, winid)
  if not package.loaded.gitsigns then
    return {}
  end

  local marks = {} --- @type Satellite.Mark[]

  --- @type {type:string, added:{start: integer, count: integer}}[]
  local hunks = require('gitsigns').get_hunks(bufnr)

  local pred = util.winbuf_pred(bufnr, winid)

  local function emit(hunk_list, signs, hl_prefix)
    for _, hunk in async.ipairs(hunk_list or {}) do
      if pred() == false then
        return false
      end
      local hl = hunk.type == 'add' and (hl_prefix .. 'Add')
        or hunk.type == 'delete' and (hl_prefix .. 'Delete')
        or (hl_prefix .. 'Change')

      local symbol = signs[hunk.type]
      if not symbol or type(symbol) ~= 'string' then
        symbol = hunk.type == 'delete' and '-' or '│'
      end

      local min_lnum = math.max(1, hunk.added.start)
      local min_pos = util.row_to_barpos(winid, min_lnum - 1)

      local max_lnum = math.max(1, hunk.added.start + math.max(0, hunk.added.count - 1))
      local max_pos = util.row_to_barpos(winid, max_lnum - 1)

      for pos = min_pos, max_pos do
        marks[#marks + 1] = {
          pos = pos,
          symbol = symbol,
          highlight = hl,
        }
      end
    end
    return true
  end

  if emit(hunks, config.signs, 'SatelliteGitSigns') == false then
    return {}
  end

  if config.staged and config.staged.enable then
    local staged_hunks = get_staged_hunks(bufnr)
    if emit(staged_hunks, config.staged.signs or config.signs, 'SatelliteGitSignsStaged') == false then
      return {}
    end
  end

  return marks
end

require('satellite.handlers').register(handler)
