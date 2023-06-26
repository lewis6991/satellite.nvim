local user_config = require 'satellite.config'.user_config

---@class SatelliteMark
---@field pos integer
---@field highlight string
---@field symbol string
---@field unique boolean
---@field count integer

---@class Handler
---@field name string
---@field ns integer
---@field setup fun(config: HandlerConfig, update: fun())
---@field update fun(bufnr: integer, winid: integer): SatelliteMark[]
---@field enabled fun(): boolean

local M = {}

local BUILTIN_HANDLERS = {
  'search',
  'diagnostic',
  'gitsigns',
  'marks',
  'cursor',
}

---@type Handler[]
M.handlers = {}

local Handler = {}

local function enabled(name)
  local handler_config = user_config.handlers[name]
  return not handler_config or handler_config.enable ~= false
end

function Handler:enabled()
  return enabled(self.name)
end

---@param spec Handler
function M.register(spec)
  vim.validate {
    spec = { spec, 'table' },
    name = { spec.name, 'string' },
    init = { spec.setup, 'function', true },
    update = { spec.update, 'function' },
  }

  spec.ns = vim.api.nvim_create_namespace('satellite.Handler.' .. spec.name)

  local h = setmetatable(spec, { __index = Handler })

  table.insert(M.handlers, h)
end

function M.init()
  -- Load builtin handlers
  for _, name in ipairs(BUILTIN_HANDLERS) do
    if enabled(name) then
      require('satellite.handlers.' .. name)
    end
  end

  local update = require('satellite.view').refresh_bars

  -- Initialize handlers
  for _, h in ipairs(M.handlers) do
    if h:enabled() and h.setup then
      h.setup(user_config.handlers[h.name], update)
    end
  end
end

return M
