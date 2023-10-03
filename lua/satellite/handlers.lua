local api = vim.api

local user_config = require 'satellite.config'.user_config
local async = require 'satellite.async'

---@class Satellite.Mark
---@field pos integer
---@field highlight string
---@field symbol string
---@field unique? boolean
---@field count? integer

---@class Satellite.Handler
---@field ns integer
---@field name string
---@field setup fun(user_config: Satellite.Handlers.BaseConfig, update: fun())
---@field update fun(bufnr: integer, winid: integer): Satellite.Mark[]
---@field enabled fun(): boolean
---@field config Satellite.Handlers.BaseConfig

---@class Satellite.HandlerRenderer: Satellite.Handler
---@field ns integer
---@field render fun(self: Satellite.Handler, winid: integer, bwinid: integer)

local M = {}

local BUILTIN_HANDLERS = {
  'search',
  'diagnostic',
  'gitsigns',
  'marks',
  'cursor',
  'quickfix',
}

---@type Satellite.HandlerRenderer[]
M.handlers = {}

local Handler = {}

local function enabled(name)
  local handler_config = user_config.handlers[name]
  return not handler_config or handler_config.enable ~= false
end

function Handler:enabled()
  return enabled(self.name)
end

--- @param bufnr integer
--- @param handler Satellite.HandlerRenderer
--- @param m Satellite.Mark
--- @param max_pos integer
local function apply_handler_mark(bufnr, handler, m, max_pos)
  if m.pos > max_pos then
    return
  end

  local opts = {
    id = not m.unique and m.pos + 1 or nil,
    priority = handler.config.priority,
  }

  if handler.config.overlap ~= false then
    opts.virt_text = { { m.symbol, m.highlight } }
    opts.virt_text_pos = 'overlay'
    opts.hl_mode = 'combine'
  else
    -- Signs are 2 chars so fill the first char with whitespace
    opts.sign_text = ' ' .. m.symbol
    opts.sign_hl_group = m.highlight
  end

  local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, handler.ns, m.pos, 0, opts)
  if not ok then
    print(
      string.format(
        'error(satellite.nvim): handler=%s buf=%d row=%d opts=%s, err="%s"',
        handler.name,
        bufnr,
        m.pos,
        vim.inspect(opts, { newline = ' ', indent = '' }),
        err
      )
    )
  end
end

---@param self Satellite.HandlerRenderer
---@param winid integer
---@param bwinid integer
Handler.render = async.void(function(self, winid, bwinid)
  if not self:enabled() then
    return
  end

  local bbufnr = api.nvim_win_get_buf(bwinid)

  if not api.nvim_buf_is_loaded(bbufnr) then
    return
  end

  local bufnr = api.nvim_win_get_buf(winid)
  local max_pos = api.nvim_buf_line_count(bbufnr) - 1

  -- async
  local marks = self.update(bufnr, winid)

  if not api.nvim_buf_is_loaded(bbufnr) or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  api.nvim_buf_clear_namespace(bbufnr, self.ns, 0, -1)

  for _, m in ipairs(marks) do
    apply_handler_mark(bbufnr, self, m, max_pos)
  end
end)

---@param spec Satellite.Handler
function M.register(spec)
  vim.validate {
    spec = { spec, 'table' },
    name = { spec.name, 'string' },
    setup = { spec.setup, 'function', true },
    update = { spec.update, 'function' },
  }

  spec.ns = api.nvim_create_namespace('satellite.Handler.' .. spec.name)

  local h = setmetatable(spec, { __index = Handler })

  table.insert(M.handlers, h)
end

local did_init = false

function M.init()
  if did_init then
    return
  end

  did_init = true

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
      h.setup(user_config.handlers[h.name] or {}, update)
    end
  end
end

return M
