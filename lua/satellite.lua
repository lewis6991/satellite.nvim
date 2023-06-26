local api = vim.api

local Handlers = require('satellite.handlers')
local Config = require 'satellite.config'
local util = require 'satellite.util'
local view = require 'satellite.view'

local M = {}

local function enable()
  view.enable()

  local gid = api.nvim_create_augroup('satellite', {})

  -- For the duration of command-line window usage, there should be no bars.
  -- Without this, bars can possibly overlap the command line window. This
  -- can be problematic particularly when there is a vertical split with the
  -- left window's bar on the bottom of the screen, where it would overlap
  -- with the center of the command line window. It was not possible to use
  -- CmdwinEnter, since the removal has to occur prior to that event. Rather,
  -- this is triggered by the WinEnter event, just prior to the relevant
  -- funcionality becoming unavailable.
  --
  -- Remove scrollbars if in cmdline. This fails when called from the
  -- CmdwinEnter event (some functionality, like nvim_win_close, cannot be
  -- used from the command line window), but works during the transition to
  -- the command line window (from the WinEnter event).
  api.nvim_create_autocmd('WinEnter', {
    group = gid,
    callback = function()
      if util.in_cmdline_win() then
        view.remove_bars()
      end
    end,
  })

  -- === Scrollbar Refreshing ===

  -- The following one ensures that the scrollbar is correctly
  -- updated after leaving a window.
  api.nvim_create_autocmd('WinLeave', {
    callback = function()
      vim.defer_fn(view.refresh_bars, 0)
    end,
  })

  api.nvim_create_autocmd({
    -- The following handles bar refreshing when changing the current window.
    'WinEnter',
    'TermEnter',

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

    'VimResized',
  }, {
    group = gid,
    callback = vim.schedule_wrap(view.refresh_bars),
  })
end

local function disable()
  view.disable()
  api.nvim_create_augroup('satellite', {})
end

-- An 'operatorfunc' for g@ that executes zf and then refreshes scrollbars.
--- @param optype 'char'|'line'
function M.zf_operator(optype)
  -- Handling for 'char' is needed since e.g., using linewise mark jumping
  -- results in the cursor moving to the beginning of the line for zfl, which
  -- should not move the cursor. Separate handling for 'line' is needed since
  -- e.g., with 'char' handling, zfG won't include the last line in the fold if
  vim.o.operatorfunc = 'v:lua:package.loaded.satellite.zf_operator<cr>g@'
  if optype == 'char' then
    vim.cmd 'silent normal! `[zf`]'
  elseif optype == 'line' then
    vim.cmd "silent normal! '[zf']"
  else
    -- Unsupported
  end
  view.refresh_bars()
end

local function apply_keymaps()
  -- === Fold command synchronization workarounds ===
  -- zf takes a motion in normal mode, so it requires a g@ mapping.
  ---@diagnostic disable-next-line: missing-parameter
  if vim.fn.maparg('zf') == '' then
    vim.keymap.set('n', 'zf', function()
      vim.o.operatorfunc = 'v:lua:package.loaded.satellite.zf_operator'
      return 'g@'
    end, { unique = true })
  end

  for _, seq in ipairs {
    'zF',
    'zd',
    'zD',
    'zE',
    'zo',
    'zO',
    'zc',
    'zC',
    'za',
    'zA',
    'zv',
    'zx',
    'zX',
    'zm',
    'zM',
    'zr',
    'zR',
    'zn',
    'zN',
    'zi',
  } do
    ---@diagnostic disable-next-line: missing-parameter
    if vim.fn.maparg(seq) == '' then
      vim.keymap.set({ 'n', 'v' }, seq, function()
        util.invalidate_virtual_line_count_cache(0)
        vim.schedule(view.refresh_bars)
        return seq
      end, { unique = true, expr = true })
    end
  end

  ---@diagnostic disable-next-line: missing-parameter
  if vim.fn.maparg('<leftmouse>') == '' then
    vim.keymap.set({ 'n', 'v', 'o', 'i' }, '<leftmouse>', function()
      require 'satellite.mouse'.handle_leftmouse()
    end)
  end
end

function M.setup(cfg)
  Config.apply(cfg)

  Handlers.init()

  apply_keymaps()

  api.nvim_create_user_command('SatelliteRefresh', view.refresh_bars, { bar = true, force = true })
  api.nvim_create_user_command('SatelliteEnable', enable, { bar = true, force = true })
  api.nvim_create_user_command('SatelliteDisable', disable, { bar = true, force = true })

  -- The default highlight group is specified below.
  -- Change this default by defining or linking an alternative highlight group.
  -- E.g., the following will use the Pmenu highlight.
  --   :highlight link ScrollView Pmenu
  -- E.g., the following will use custom highlight colors.
  --   :highlight ScrollView ctermbg=159 guibg=LightCyan
  api.nvim_set_hl(0, 'ScrollView', { default = true, link = 'Visual' })

  enable()
end

return M
