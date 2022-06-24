local util = require'satellite.util'
local view = require'satellite.view'

local highlight = 'Normal'

---@type Handler
local handler = {
  name = 'marks',
}

local BUILTIN_MARKS = { "'.", "'^", "''", "'\"", "'<", "'>", "'[", "']" }

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

---@param m string mark name
local function mark_set_keymap(m)
    local map = 'm' .. m
    ---@diagnostic disable-next-line: missing-parameter
    if vim.fn.maparg(map) == "" then
      vim.keymap.set({ 'n', 'v' }, map, function()
        local bufnr = vim.api.nvim_get_current_buf()
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        local mline, mcol = unpack(vim.api.nvim_buf_get_mark(bufnr, m))
        if mline == line and mcol == col then
            vim.api.nvim_buf_del_mark(bufnr, m)
        else
            vim.api.nvim_buf_set_mark(bufnr, m, line, col, {})
        end
        vim.schedule(view.refresh_bars)
      end)
    end
end

function handler.init(config0)
  config = config0

  -- range over A-Z
  for code = 65, 90 do
    mark_set_keymap(string.char(code))
  end

  -- -- range over a-z
  for code = 97, 122 do
    mark_set_keymap(string.char(code))
  end

  local group = vim.api.nvim_create_augroup('satellite_marks', {})
  for _, cmd in ipairs{'k', 'mar', 'delm'} do
    util.on_cmd(cmd, group, function()
      vim.schedule(view.refresh_bars)
    end)
  end

end

local function add_mark_to_bar(marks, mark, winid)
    local lnum = mark.pos[2]
    local pos = util.row_to_barpos(winid, lnum-1)

    if config and config.show_builtins or not mark_is_builtin(mark.mark) then
        marks[#marks+1] = {
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
