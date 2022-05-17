
---@class Handler
---@field name string
---@field ns integer
---@field init fun()
---@field update fun(bufnr: integer,user_config: table)

local M = {}

---@type Handler[]
M.handlers = {}

---@param spec Handler
function M.register(spec)
  vim.validate{
    spec   = {spec       , 'table'  },
    name   = {spec.name  , 'string' },
    init   = {spec.init  , 'function', true },
    update = {spec.update, 'function' },
  }

  if spec.init then
    local orig_update = spec.update
    spec.update = function(...)
      spec.init()
      spec.update = orig_update
      return spec.update(...)
    end
  end

  spec.ns = vim.api.nvim_create_namespace('satellite.Handler.'..spec.name)
  table.insert(M.handlers, spec)
end

return M
