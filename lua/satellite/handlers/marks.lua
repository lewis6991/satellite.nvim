local util = require'satellite.util'


---@type Handler
local handler = {
  name = 'marks',
}

local BUILTIN_MARKS = { "'.", "'^", "''", "'\"", "'<", "'>", "'[", "']" }

local config = {}

local function refresh()
  require('satellite').refresh_bars()
end

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

function handler.init(user_config)
  config = user_config

  -- range over a-z
  for char = 97, 122 do
    local map = 'm' .. string.char(char)
    vim.keymap.set({ 'n', 'v' }, map, function()
      vim.schedule(refresh)
      return map
    end, { unique = true, expr = true })
  end

  local group = vim.api.nvim_create_augroup('satellite_marks', {})

  for _, cmd in ipairs{'k', 'mar', 'delm'} do
    util.on_cmd(cmd, group, function()
      vim.schedule(function()
        require('satellite').refresh_bars()
      end)
    end)
  end

end

function handler.update(bufnr, winid)
  local marks = {}
  local buffer_marks = vim.fn.getmarklist(bufnr)
  for _, mark in ipairs(buffer_marks) do
    local lnum = mark.pos[2]

    local pos = util.row_to_barpos(winid, lnum-1)

    if config and config.show_builtins or not mark_is_builtin(mark.mark) then
      marks[pos] = {
        -- first char of mark name is a single quote
        symbol = string.sub(mark.mark, 2, 3),
      }
    end
  end

  local ret = {}

  for pos, mark in pairs(marks) do
    ret[#ret+1] = {
      pos = pos,
      highlight = config.highlight,
      symbol = mark.symbol,
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
