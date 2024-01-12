local api = vim.api

local util = require 'satellite.util'

local HIGHLIGHT = 'SatelliteMark'

--- @type Satellite.Handler
local handler = {
  name = 'marks',
}

local function setup_hl()
  api.nvim_set_hl(0, HIGHLIGHT, {
    default = true,
    fg = api.nvim_get_hl(0, { name = 'Normal' }).fg,
  })
end

local BUILTIN_MARKS = { "'.", "'^", "''", '\'"', "'<", "'>", "'[", "']" }

--- @class Satellite.Handlers.MarksConfig: Satellite.Handlers.BaseConfig
--- @field key    string
--- @field show_builtins boolean
local config = {
  key = 'm',
  overlap = true,
  priority = 60,
  show_builtins = false,
}

--- @param m string mark name
--- @return boolean
local function mark_is_builtin(m)
  return vim.list_contains(BUILTIN_MARKS, m)
end

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  require('satellite.autocmd.mark')(config.key)

  local group = api.nvim_create_augroup('satellite_marks', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'Mark',
    callback = vim.schedule_wrap(update),
  })
end

--- @param marks Satellite.Mark[]
--- @param mark {pos: {[1]:integer, [2]:integer}, mark: string}
--- @param winid integer
local function add_mark_to_bar(marks, mark, winid)
  local lnum = mark.pos[2]
  local pos = util.row_to_barpos(winid, lnum - 1)

  if config and config.show_builtins or not mark_is_builtin(mark.mark) then
    marks[#marks + 1] = {
      pos = pos,
      highlight = HIGHLIGHT,
      -- first char of mark name is a single quote
      symbol = string.sub(mark.mark, 2, 3),
    }
  end
end

function handler.update(bufnr, winid)
  local ret = {}

  local current_file = vim.api.nvim_buf_get_name(bufnr)
  for _, mark in ipairs(vim.fn.getmarklist()) do
    local mark_file = vim.fn.fnamemodify(mark.file, ':p:a')
    if mark_file == current_file and mark.mark:find('[a-zA-Z]') ~= nil then
      add_mark_to_bar(ret, mark, winid)
    end
  end

  for _, mark in ipairs(vim.fn.getmarklist(bufnr)) do
    add_mark_to_bar(ret, mark, winid)
  end

  return ret
end

require('satellite.handlers').register(handler)
