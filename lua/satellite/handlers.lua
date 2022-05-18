local user_config = require'satellite.config'.user_config

---@class Handler
---@field name string
---@field ns integer
---@field init fun(config: Config)
---@field update fun(bufnr: integer, winid, integer)

local M = {}

local BUILTIN_HANDLERS = {
  'search',
  'diagnostic',
  'gitsigns',
  'marks',
}

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

  spec.ns = vim.api.nvim_create_namespace('satellite.Handler.'..spec.name)
  table.insert(M.handlers, spec)
end

function M.enabled(name)
  local handler_config = user_config.handlers[name]
  return not handler_config or handler_config.enable ~= false
end

function M.init()

  -- Load builtin handlers
  for _, name in ipairs(BUILTIN_HANDLERS) do
    if M.enabled(name) then
      require('satellite.handlers.'..name)
    end
  end

  for _, h in ipairs(M.handlers) do
    if M.enabled(h.name) and h.init then
      h.init(user_config.handlers[h.name])
    end
  end
end

return M
