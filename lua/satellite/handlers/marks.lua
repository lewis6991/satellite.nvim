local highlight = 'Normal'

---@type Handler
local handler = {
  name = 'marks',
}

local function refresh()
  require('satellite').refresh_bars()
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
    marks[#marks + 1] = {
      -- [bufnum, lnum, col, off]
      lnum = mark.pos[2] + 1,
      -- first char of mark name is a single quote
      symbol = string.sub(mark.mark, 2, 3),
      highlight = highlight,
    }
  end
  return marks
end

require('satellite.handlers').register(handler)
