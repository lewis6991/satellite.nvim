local highlight = 'Normal'

---@type Handler
local handler = {
  name = 'marks',
}

local builtin_marks = { '\'.', '\'^', '\'\'', '\'"', '\'<', '\'>', '\'[', '\']' }

local function refresh()
  require('satellite').refresh_bars()
end

---@param m string mark name
---@return boolean
local function its_a_builtin_mark(m)
  for _, mark in pairs(builtin_marks) do
    if mark == m then
      return true
    end
  end
  return false
end

function handler.init()
  -- range over a-z
  for char = 97, 122 do
    local map = 'm' .. string.char(char)
    vim.keymap.set({ 'n', 'v' }, map, function()
      vim.schedule(refresh)
      return map
    end, { unique = true, expr = true })
  end
end

function handler.update(bufnr)
  local marks = {}
  local buffer_marks = vim.fn.getmarklist(bufnr)
  for _, mark in ipairs(buffer_marks) do
    if not its_a_builtin_mark(mark.mark) then
      marks[#marks + 1] = {
        -- [bufnum, lnum, col, off]
        lnum = mark.pos[2],
        -- first char of mark name is a single quote
        symbol = string.sub(mark.mark, 2, 3),
        highlight = highlight,
      }
    end
  end
  return marks
end

require('satellite.handlers').register(handler)
