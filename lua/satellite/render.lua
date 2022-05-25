local api = vim.api

local async = require'satellite.async'
local user_config = require'satellite.config'.user_config
local Handlers = require'satellite.handlers'

local M = {}

local ns = api.nvim_create_namespace('satellite')

---@param winid integer
---@param bbufnr integer
---@param row integer
---@param height integer
local function render_scrollbar(winid, bbufnr, row, height)
  local winheight = api.nvim_win_get_height(winid)

  local lines = {}
  for i = 1, winheight do
    lines[i] = ' '
  end

  vim.bo[bbufnr].modifiable = true
  api.nvim_buf_set_lines(bbufnr, 0, -1, true, lines)
  vim.bo[bbufnr].modifiable = false

  for i = row, row+height do
    pcall(api.nvim_buf_set_extmark, bbufnr, ns, i, 0, {
      virt_text = { {' ', 'ScrollView'} },
      virt_text_pos = 'overlay',
      priority = 1,
    })
  end
end

---@param bufnr integer
---@param winid integer
---@param bbufnr integer
---@param handler Handler
local function render_handler(bufnr, winid, bbufnr, handler)
  local name = handler.name

  if not handler:enabled() then
    return
  end

  local handler_config = user_config.handlers[name] or {}

  for _, m in ipairs(handler.update(bufnr, winid)) do
    local pos, symbol = m.pos, m.symbol

    local opts = {
      id = not m.unique and pos+1 or nil,
      priority = handler_config.priority
    }

    if handler_config.overlap ~= false then
      opts.virt_text = {{symbol, m.highlight}}
      opts.virt_text_pos = 'overlay'
      opts.hl_mode = 'combine'
    else
      -- Signs are 2 chars so fill the first char with whitespace
      opts.sign_text = ' '..symbol
      opts.sign_hl_group = m.highlight
    end

    local ok, err = pcall(api.nvim_buf_set_extmark, bbufnr, handler.ns, pos, 0, opts)
    if not ok then
      print(string.format('%s ROW: %d', handler.name, pos))
      print(err)
    end
  end
end

---@param winid integer
---@param bar_winid integer
local function reposition_bar(winid, bar_winid)
  local winwidth = api.nvim_win_get_width(winid)
  local wininfo = vim.fn.getwininfo(bar_winid)[1]
  local signwidth = wininfo.textoff
  local col = winwidth - signwidth

  api.nvim_win_set_config(bar_winid, {
    relative = 'win',
    row = 0,
    col = col,
    width = 1 + signwidth,
  })

  vim.w[bar_winid].col = col
end

---@param bbufnr integer
---@param bwinid integer
---@param winid integer
---@param row integer
---@param height integer
M.render_bar = async.void(function(bbufnr, bwinid, winid, row, height)
  render_scrollbar(winid, bbufnr, row, height)

  -- Run handlers
  local bufnr = api.nvim_win_get_buf(winid)
  for _, handler in ipairs(Handlers.handlers) do
    render_handler(bufnr, winid, bbufnr, handler)
  end

  reposition_bar(winid, bwinid)
end)

return M
