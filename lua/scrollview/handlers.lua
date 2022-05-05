
---@class Handler
---@field name string
---@field callback fun(bufnr: integer)

local M = {}

---@type Handler[]
M.handlers = {}

function M.register(name, callback)
  table.insert(M.handlers, {
    name = name,
    callback = callback
  })
end

return M
