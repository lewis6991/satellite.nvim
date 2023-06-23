local util = require 'satellite.util'
local view = require 'satellite.view'

local highlight = 'MarkSV'

local api = vim.api

require 'satellite.autocmd.mark'

---@type Handler
local handler = {
  name = 'marks',
}

local function setup_hl()
  api.nvim_set_hl(0, highlight, {
    default = true,
    fg = api.nvim_get_hl_by_name('Normal', true).foreground,
  })
end

local BUILTIN_MARKS = { "'.", "'^", "''", '\'"', "'<", "'>", "'[", "']" }

local config = {}

---@param m string mark name
---@return boolean
local function mark_is_builtin(m)
  for _, mark in pairs(BUILTIN_MARKS) do
    if mark == m then
      return true
    end
  end
  return false
end

function handler.init(config0, update)
  config = config0

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

---@param marks SatelliteMark[]
---@param mark {pos: {[1]:integer, [2]:integer}, mark: string}
---@param winid integer
local function add_mark_to_bar(marks, mark, winid)
  local lnum = mark.pos[2]
  local pos = util.row_to_barpos(winid, lnum - 1)

  if config and config.show_builtins or not mark_is_builtin(mark.mark) then
    marks[#marks + 1] = {
      pos = pos,
      highlight = highlight,
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
