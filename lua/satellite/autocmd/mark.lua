--- This module implements a user autocmd for Mark events

local util = require 'satellite.util'
local config = require 'satellite.config'

local api, fn = vim.api, vim.fn

local function exec_autocmd(data)
  api.nvim_exec_autocmds('User', {
    pattern = 'Mark',
    data = data,
  })
end

local group = api.nvim_create_augroup('satellite_autocmd_mark', {})

---@param m string mark name
local function mark_set_keymap(m)
  local key = config.user_config.handlers.marks.key .. m
  if fn.maparg(key) == '' then
    vim.keymap.set({ 'n', 'x' }, key, function()
      exec_autocmd { key = key }
      return key
    end, { unique = true, expr = true })
  end
end

for code = string.byte('A'), string.byte('Z') do
  mark_set_keymap(string.char(code))
end

for code = string.byte('a'), string.byte('z') do
  mark_set_keymap(string.char(code))
end

for _, cmd in ipairs { 'k', 'mar', 'delm' } do
  util.on_cmd(cmd, group, function()
    exec_autocmd { cmd = cmd }
  end)
end
