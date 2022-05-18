local api = vim.api

local util = require'satellite.util'
local user_config = require'satellite.config'.user_config
local Handlers = require'satellite.handlers'

local M = {}

local ns = api.nvim_create_namespace('satellite')

---@param count integer
---@param s string|string[]
local function get_symbol(count, s)
  if type(s) == 'string' then
    return s
  end
  return s[count] or s[#s]
end

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

  if not Handlers.enabled(name) then
    return
  end

  local handler_config = user_config.handlers[name] or {}

  local positions = {}
  for _, m in ipairs(handler.update(bufnr, winid)) do
    local pos = m.pos or util.row_to_barpos(winid, m.lnum-1)
    positions[pos] = (positions[pos] or 0) + 1
    local symbol = get_symbol(positions[pos], m.symbol)

    local opts = {
      id = not m.unique and pos+1 or nil,
      priority = (handler_config.priority or 1)*10 + positions[pos]
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
  -- Reposition window if we need to
  local winwidth = api.nvim_win_get_width(winid)
  local signwidth = vim.fn.getwininfo(bar_winid)[1].textoff
  local col = winwidth - signwidth - 1

  local cfg = api.nvim_win_get_config(bar_winid)
  ---@diagnostic disable-next-line: undefined-field
  if cfg.col ~= col then
    local ok, err = pcall(api.nvim_win_set_config, bar_winid, {col = col})
    if ok then
      print(col)
      error(err)
    end
  end
end

---@param bbufnr integer
---@param bwinid integer
---@param winid integer
---@param row integer
---@param height integer
function M.render_bar(bbufnr, bwinid, winid, row, height)
  render_scrollbar(winid, bbufnr, row, height)

  -- Run handlers
  local bufnr = api.nvim_win_get_buf(winid)
  for _, handler in ipairs(Handlers.handlers) do
    render_handler(bufnr, winid, bbufnr, handler)
  end

  reposition_bar(winid, bwinid)
end

return M
