local api = vim.api
local fn = vim.fn

local Handlers = require('satellite.handlers')
local util = require'satellite.util'
local Config = require'satellite.config'
local render = require'satellite.render'
local mouse = require'satellite.mouse'
local state = require'satellite.state'

local user_config = Config.user_config

local M = {}

local function create_view(cfg)
  local bufnr = api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = 'delete'
  vim.bo[bufnr].buflisted = false

  local winid = api.nvim_open_win(bufnr, false, cfg)

  -- It's not sufficient to just specify Normal highlighting. With just that, a
  -- color scheme's specification of EndOfBuffer would be used to color the
  -- bottom of the scrollbar.
  util.set_window_option(winid, "winhighlight", 'Normal:Normal')
  util.set_window_option(winid, "winblend", user_config.winblend)
  util.set_window_option(winid, "foldcolumn" , '0')
  util.set_window_option(winid, "wrap" , false)

  return bufnr, winid
end

local function in_cmdline_win(winid)
  winid = winid or api.nvim_get_current_win()
  if not api.nvim_win_is_valid(winid) then
    return false
  end
  if fn.win_gettype(winid) == 'command' then
    return true
  end
  local bufnr = api.nvim_win_get_buf(winid)
  return api.nvim_buf_get_name(bufnr) == '[Command Line]'
end

-- Show a scrollbar for the specified 'winid' window ID, using the specified
-- 'bar_winid' floating window ID (a new floating window will be created if
-- this is -1). Returns -1 if the bar is not shown, and the floating window ID
-- otherwise.
local function show_scrollbar(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local buf_filetype = vim.bo[bufnr].filetype

  util.invalidate_virtual_line_count_cache(winid)

  -- Skip if the filetype is on the list of exclusions.
  if vim.tbl_contains(user_config.excluded_filetypes, buf_filetype) then
    return
  end

  local wininfo = fn.getwininfo(winid)[1]

  -- Don't show in terminal mode, since the bar won't be properly updated for
  -- insertions.
  if wininfo.terminal ~= 0 then
    return
  end

  if in_cmdline_win(winid) then
    return
  end

  local winheight = api.nvim_win_get_height(winid)
  local winwidth = api.nvim_win_get_width(winid)
  if winheight == 0 or winwidth == 0 then
    return
  end
  if vim.fn.has("nvim-0.8") > 0 then
    if vim.o.winbar ~= '' then
        winheight = winheight - 1
    end
  end

  local line_count = api.nvim_buf_line_count(bufnr)

  if line_count == 0 then
    return
  end

  -- Don't show the position bar when all lines are on screen.
  local topline, botline = util.visible_line_range(winid)
  if botline - topline + 1 == line_count then
    return
  end

  local cfg = {
    win = winid,
    relative = 'win',
    style = 'minimal',
    focusable = false,
    zindex = user_config.zindex,
    height = winheight,
    width = 1,
    row = 0,
    col = winwidth - 1
  }

  local bar_winid = state.winids[winid]
  local bar_bufnr

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
    bar_bufnr = api.nvim_win_get_buf(bar_winid)
  else
    cfg.noautocmd = true
    bar_bufnr, bar_winid = create_view(cfg)
    state.winids[winid] = bar_winid
  end

  local toprow = util.row_to_barpos(winid, topline - 1)
  local height = util.height_to_virtual(winid, topline - 1, botline - 1)
  render.render_bar(bar_bufnr, bar_winid, winid, toprow, height)

  vim.w[bar_winid].height = height
  vim.w[bar_winid].row = toprow
  vim.w[bar_winid].col = cfg.col
  vim.w[bar_winid].width = cfg.width

  return true
end

local function noautocmd(f)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = 'all'
  f()
  vim.o.eventignore = eventignore
end

local function close_view_for_win(winid)
  local bar_winid = state.winids[winid]
  if not api.nvim_win_is_valid(bar_winid) then
    return
  end
  if in_cmdline_win(winid) then
    return
  end
  noautocmd(function()
    api.nvim_win_close(bar_winid, true)
  end)
  state.winids[winid] = nil
end

function M.remove_bars()
  for id, _ in pairs(state.winids) do
    close_view_for_win(id)
  end
end

local function get_target_windows()
  local target_wins
  if user_config.current_only then
    target_wins = { api.nvim_get_current_win() }
  else
    target_wins = {}
    local current_tab = api.nvim_get_current_tabpage()
    for _, winid in ipairs(api.nvim_list_wins()) do
      if util.is_ordinary_window(winid) and api.nvim_win_get_tabpage(winid) == current_tab then
        target_wins[#target_wins+1] = winid
      end
    end
  end
  return target_wins
end

-- Refreshes scrollbars. Global state is initialized and restored.
function M.refresh_bars()
  local current_wins = {}

  if state.view_enabled then
    for _, winid in ipairs(get_target_windows()) do
      if show_scrollbar(winid) then
        current_wins[#current_wins+1] = state.winids[winid]
      end
    end
  end

  -- Close any remaining bars
  for winid, swinid in pairs(state.winids) do
    if not vim.tbl_contains(current_wins, swinid) then
      close_view_for_win(winid)
    end
  end
end

local function enable()
  state.view_enabled = true

  local gid = api.nvim_create_augroup('satellite', {})

  -- The following error can arise when the last window in a tab is going to
  -- be closed, but there are still open floating windows, and at least one
  -- other tab.
  --   > "E5601: Cannot close window, only floating window would remain"
  -- Neovim Issue #11440 is open to address this. As of 2020/12/12, this
  -- issue is a 0.6 milestone.
  -- The autocmd below removes bars subsequent to :quit, :wq, or :qall (and
  -- also ZZ and ZQ), to avoid the error. However, the error will still arise
  -- when <ctrl-w>c or :close are used. To avoid the error in those cases,
  -- <ctrl-w>o can be used to first close the floating windows, or
  -- alternatively :tabclose can be used (or one of the alternatives handled
  -- with the autocmd, like ZQ).
  api.nvim_create_autocmd('QuitPre', { group = gid, callback = M.remove_bars })

  -- For the duration of command-line window usage, there should be no bars.
  -- Without this, bars can possibly overlap the command line window. This
  -- can be problematic particularly when there is a vertical split with the
  -- left window's bar on the bottom of the screen, where it would overlap
  -- with the center of the command line window. It was not possible to use
  -- CmdwinEnter, since the removal has to occur prior to that event. Rather,
  -- this is triggered by the WinEnter event, just prior to the relevant
  -- funcionality becoming unavailable.
  --
  -- Remove scrollbars if in cmdlnie. This fails when called from the
  -- CmdwinEnter event (some functionality, like nvim_win_close, cannot be
  -- used from the command line window), but works during the transition to
  -- the command line window (from the WinEnter event).
  api.nvim_create_autocmd('WinEnter', {group = gid, callback = function()
    if in_cmdline_win() then
      M.remove_bars()
    end
  end})

  -- === Scrollbar Refreshing ===
  api.nvim_create_autocmd({
    -- The following handles bar refreshing when changing the current window.
    'WinEnter', 'TermEnter',

    -- The following restores bars after leaving the command-line window.
    -- Refreshing must be asynchronous, since the command line window is still
    -- in an intermediate state when the CmdwinLeave event is triggered.
    'CmdwinLeave',

    -- The following handles scrolling events, which could arise from various
    -- actions, including resizing windows, movements (e.g., j, k), or
    -- scrolling (e.g., <ctrl-e>, zz).
    'WinScrolled',

    -- The following handles the case where text is pasted. TextChangedI is not
    -- necessary since WinScrolled will be triggered if there is corresponding
    -- scrolling.
    'TextChanged',

    -- The following handles when :e is used to load a file.
    'BufWinEnter',

    -- The following is used so that bars are shown when cycling through tabs.
    'TabEnter',

    'VimResized'
  }, {
    group = gid,
    callback = M.refresh_bars
  })

  M.refresh_bars()
end

local function disable()
  state.view_enabled = false
  api.nvim_create_augroup('satellite', {})
  M.remove_bars()
end


-- An 'operatorfunc' for g@ that executes zf and then refreshes scrollbars.
function M.zf_operator(type)
  -- Handling for 'char' is needed since e.g., using linewise mark jumping
  -- results in the cursor moving to the beginning of the line for zfl, which
  -- should not move the cursor. Separate handling for 'line' is needed since
  -- e.g., with 'char' handling, zfG won't include the last line in the fold if
    vim.o.operatorfunc = 'v:lua:package.loaded.satellite.zf_operator<cr>g@'
  if type == 'char' then
    vim.cmd"silent normal! `[zf`]"
  elseif type == 'line' then
    vim.cmd"silent normal! '[zf']"
  else
    -- Unsupported
  end
  M.refresh_bars()
end

local function apply_keymaps()
  -- === Fold command synchronization workarounds ===
  -- zf takes a motion in normal mode, so it requires a g@ mapping.
  ---@diagnostic disable-next-line: missing-parameter
  if vim.fn.maparg('zf') == "" then
    vim.keymap.set('n', 'zf', function()
      vim.o.operatorfunc = 'v:lua:package.loaded.satellite.zf_operator'
      return 'g@'
    end, {unique = true})
  end

  for _, seq in ipairs{
    'zF', 'zd', 'zD', 'zE', 'zo', 'zO', 'zc', 'zC', 'za', 'zA', 'zv',
    'zx', 'zX', 'zm', 'zM', 'zr', 'zR', 'zn', 'zN', 'zi'
  } do
    ---@diagnostic disable-next-line: missing-parameter
    if vim.fn.maparg(seq) == "" then
      vim.keymap.set({'n', 'v'}, seq, function()
        vim.schedule(M.refresh_bars)
        return seq
      end, {unique = true, expr=true})
    end
  end

  ---@diagnostic disable-next-line: missing-parameter
  if vim.fn.maparg('<leftmouse>') == "" then
    vim.keymap.set({'n', 'v', 'o', 'i'}, '<leftmouse>', function()
      mouse.handle_leftmouse(M.refresh_bars)
    end)
  end
end

function M.setup(cfg)
  Config.apply(cfg)

  Handlers.init()

  apply_keymaps()

  api.nvim_create_user_command('SatelliteRefresh', M.refresh_bars, { bar = true, force = true})
  api.nvim_create_user_command('SatelliteEnable' , enable ,        { bar = true, force = true})
  api.nvim_create_user_command('SatelliteDisable', disable,        { bar = true, force = true})

  -- The default highlight group is specified below.
  -- Change this default by defining or linking an alternative highlight group.
  -- E.g., the following will use the Pmenu highlight.
  --   :highlight link ScrollView Pmenu
  -- E.g., the following will use custom highlight colors.
  --   :highlight ScrollView ctermbg=159 guibg=LightCyan
  api.nvim_set_hl(0, 'ScrollView', {default = true, link = 'Visual' })

  enable()
end

return M
