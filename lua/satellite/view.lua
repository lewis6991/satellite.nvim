local fn, api = vim.fn, vim.api

local util = require 'satellite.util'

local user_config = require 'satellite.config'.user_config

local ns = api.nvim_create_namespace('satellite')

local M = {}

local enabled = false

--- @type table<integer,integer?>
local winids = {}

--- @param win integer
--- @param opt string
--- @param value string|boolean|integer
local function set_winlocal_opt(win, opt, value)
  -- Set local=scope so options are never inherited in new windows
  api.nvim_set_option_value(opt, value, { win = win, scope = 'local' })
end

--- @param cfg table
--- @return integer winid
local create_view = util.noautocmd(function(cfg)
  local bufnr = api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buflisted = false
  -- Don't store undo information to reduce memory usage
  vim.bo[bufnr].undolevels = -1

  cfg.noautocmd = true
  local winid = api.nvim_open_win(bufnr, false, cfg)

  -- It's not sufficient to just specify Normal highlighting. With just that, a
  -- color scheme's specification of EndOfBuffer would be used to color the
  -- bottom of the scrollbar.
  set_winlocal_opt(winid, 'winhighlight', 'Normal:Normal')
  set_winlocal_opt(winid, 'winblend', user_config.winblend)
  set_winlocal_opt(winid, 'foldcolumn', '0')
  set_winlocal_opt(winid, 'wrap', false)

  return winid
end)

--- @param winid integer
--- @param bwinid integer
local function render_scrollbar(winid, bwinid)
  local bbufnr = api.nvim_win_get_buf(bwinid)
  local winheight = util.get_winheight(winid)

  -- Initialise buffer lines if needed
  if api.nvim_buf_line_count(bbufnr) ~= winheight then
    local lines = {} --- @type string[]
    for i = 1, winheight do
      lines[i] = ' '
    end

    vim.bo[bbufnr].modifiable = true
    api.nvim_buf_set_lines(bbufnr, 0, -1, true, lines)
    vim.bo[bbufnr].modifiable = false
  end

  local height = vim.w[bwinid].height --- @type integer
  local row = vim.w[bwinid].row --- @type integer

  api.nvim_buf_clear_namespace(bbufnr, ns, 0, -1)
  -- Set bar colors with virtual text for each line.
  for i = 0, winheight - 1 do
    -- Background color
    local style = 'SatelliteBackground'
    -- Bar color
    if i >= row and i < row + height then
      style = 'SatelliteBar'
    end

    pcall(api.nvim_buf_set_extmark, bbufnr, ns, i, 0, {
      virt_text = { { ' ', style } },
      virt_text_pos = 'overlay',
      priority = 1,
    })
  end
end

--- Get or retrieve a bar window id for a given window
--- @param winid integer
--- @return integer bar_winid
local function get_or_create_view(winid)
  local cfg = {
    win = winid,
    relative = 'win',
    style = 'minimal',
    focusable = false,
    zindex = user_config.zindex,
    width = 1,
    row = 0,
    height = util.get_winheight(winid),
    col = api.nvim_win_get_width(winid) - 1,
  }

  local bar_winid = winids[winid]
  if bar_winid then
    local bar_wininfo = vim.fn.getwininfo(bar_winid)[1]
    -- wininfo can be nil when pressing <C-w>o in help buffers
    if bar_wininfo then
      local signwidth = bar_wininfo.textoff
      cfg.col = cfg.col - signwidth
      cfg.width = cfg.width + signwidth
    end
  end

  if bar_winid and api.nvim_win_is_valid(bar_winid) then
    api.nvim_win_set_config(bar_winid, cfg)
  else
    bar_winid = create_view(cfg)
    winids[winid] = bar_winid
  end

  local topline, botline = util.visible_line_range(winid)
  local toprow = util.row_to_barpos(winid, topline - 1)
  local height = util.height_to_virtual(winid, topline - 1, botline - 1)

  vim.w[bar_winid].col = cfg.col
  vim.w[bar_winid].width = cfg.width
  vim.w[bar_winid].height = height
  vim.w[bar_winid].row = toprow

  return bar_winid
end

--- @param bwinid integer
--- @param winid integer
local function render(bwinid, winid)
  util.invalidate_virtual_line_count_cache(winid)

  render_scrollbar(winid, bwinid)

  local Handlers = require('satellite.handlers')

  Handlers.render(bwinid, winid)
end

local function is_terminal(winid)
  return fn.getwininfo(winid)[1].terminal ~= 0
end

--- @param winid integer
--- @return boolean
local function can_show_scrollbar(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local buf_filetype = vim.bo[bufnr].filetype

  -- Skip if the filetype is on the list of exclusions.
  if vim.tbl_contains(user_config.excluded_filetypes, buf_filetype) then
    return false
  end

  -- Don't show in terminal mode, since the bar won't be properly updated for
  -- insertions.
  if is_terminal(winid) then
    return false
  end

  if util.in_cmdline_win(winid) then
    return false
  end

  if util.get_winheight(winid) == 0 or api.nvim_win_get_width(winid) == 0 then
    return false
  end

  local line_count = api.nvim_buf_line_count(bufnr)

  if line_count == 0 then
    return false
  end

  -- Don't show the position bar when all lines are on screen.
  local topline, botline = util.visible_line_range(winid)
  if botline - topline + 1 == line_count then
    return false
  end

  return true
end

--- Returns view properties for the specified window. An empty dictionary
--- is returned if there is no corresponding scrollbar.
--- @param winid integer
--- @return {height:integer, row: integer, col: integer, width:integer}?
function M.get_props(winid)
  local bar_winid = winids[winid]
  if not bar_winid then
    return
  end

  return {
    height = vim.w[bar_winid].height,
    row = vim.w[bar_winid].row,
    col = vim.w[bar_winid].col,
    width = vim.w[bar_winid].width,
  }
end

--- @return integer[]
local function get_target_windows()
  if user_config.current_only then
    return { api.nvim_get_current_win() }
  end

  local target_wins = {} --- @type integer[]
  local current_tab = api.nvim_get_current_tabpage()
  for _, winid in ipairs(api.nvim_list_wins()) do
    if util.is_ordinary_window(winid) and api.nvim_win_get_tabpage(winid) == current_tab then
      target_wins[#target_wins + 1] = winid
    end
  end
  return target_wins
end

--- @param winid integer
local function close(winid)
  util.invalidate_virtual_line_count_cache(winid)
  local bar_winid = winids[winid]
  if not bar_winid then
    return
  end
  if not api.nvim_win_is_valid(bar_winid) then
    return
  end
  if util.in_cmdline_win(winid) then
    return
  end
  util.noautocmd(api.nvim_win_close)(bar_winid, true)
  winids[winid] = nil
end

function M.refresh_bars()
  local current_bar_wins = {} --- @type integer[]

  if enabled then
    for _, winid in ipairs(get_target_windows()) do
      if can_show_scrollbar(winid) then
        -- pcall in case the window cannot be changed (#76)
        local ok, bwinid_or_err = pcall(get_or_create_view, winid)
        if ok then
          render(bwinid_or_err, winid)
          current_bar_wins[#current_bar_wins + 1] = bwinid_or_err
        else
          vim.notify(debug.traceback('satellite.nvim: unable to get a view'), vim.log.levels.ERROR)
        end
      end
    end
  end

  -- Close any remaining bars
  for winid, bwinid in pairs(winids) do
    if not vim.tbl_contains(current_bar_wins, bwinid) then
      close(winid)
    end
  end
end

function M.remove_bars()
  for winid, _ in pairs(winids) do
    close(winid)
  end
end

function M.disable()
  enabled = false
  M.remove_bars()
end

function M.enable()
  enabled = true
  M.refresh_bars()
end

function M.enabled()
  return enabled
end

return M
