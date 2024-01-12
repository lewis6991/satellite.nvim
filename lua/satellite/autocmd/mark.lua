--- This module implements a user autocmd for Mark events

local util = require 'satellite.util'

local api, fn = vim.api, vim.fn

--- @param data any
local function exec_autocmd(data)
  api.nvim_exec_autocmds('User', {
    pattern = 'Mark',
    data = data,
  })
end

--- @param key string
--- @param m string mark name
local function mark_set_keymap(key, m)
  local mkey = key .. m
  if fn.maparg(mkey) == '' then
    vim.keymap.set({ 'n', 'x' }, mkey, function()
      exec_autocmd { key = mkey }
      return mkey
    end, { unique = true, expr = true })
  end
end

--- @param key string
return function(key)
  for code = string.byte('A'), string.byte('Z') do
    mark_set_keymap(key, string.char(code))
  end

  for code = string.byte('a'), string.byte('z') do
    mark_set_keymap(key, string.char(code))
  end

  local group = api.nvim_create_augroup('satellite_autocmd_mark', {})

  for _, cmd in ipairs { 'k', 'mar', 'delm' } do
    util.on_cmd(cmd, group, function()
      exec_autocmd { cmd = cmd }
    end)
  end
end
