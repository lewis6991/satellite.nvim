
---@class Handler
---@field name string
---@field ns integer
---@field callback fun(bufnr: integer)

local M = {}

---@type Handler[]
M.handlers = {}

function M.register(name, callback)
  table.insert(M.handlers, {
    name = name,
    ns = vim.api.nvim_create_namespace('scrollview.Handler.'..name),
    callback = callback
  })
end

return M
