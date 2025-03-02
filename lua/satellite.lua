local api = vim.api

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
    vim.cmd "silent normal! '[zf']"
  elseif optype == 'line' then
    vim.cmd "silent normal! '[zf']"
  else
    -- Unsupported
  end
  view.refresh_bars()
end

local foldmaps = {
  zF = true,
  zd = true,
  zD = true,
  zE = true,
  zo = true,
  zO = true,
  zc = true,
  zC = true,
  za = true,
  zA = true,
  zv = true,
  zx = true,
  zX = true,
  zm = true,
  zM = true,
  zr = true,
  zR = true,
  zn = true,
  zN = true,
  zi = true,
}

local function apply_keymaps()
  if vim.fn.maparg('<leftmouse>') == '' then
    vim.keymap.set({ 'n', 'v', 'o', 'i' }, '<leftmouse>', function()
      require 'satellite.mouse'.handle_leftmouse()
    end)
  end

  local version = vim.version()
  if version.major == 0 and version.minor >= 11 then
    local prev = ''
    vim.on_key(function(_, typed)
      if typed == 'z' then
        prev = 'z'
        return
      end
      local seq = prev .. typed
      if foldmaps[seq] or seq == 'zf' then
        util.invalidate_virtual_line_count_cache(0)
        vim.schedule(view.refresh_bars)
      end
      prev = ''
    end)
  else
    -- === Fold command synchronization workarounds ===
    -- zf takes a motion in normal mode, so it requires a g@ mapping.
    if vim.fn.maparg('zf') == '' then
      vim.keymap.set('n', 'zf', function()
        vim.o.operatorfunc = 'v:lua.package.loaded.satellite.zf_operator'
        return 'g@'
      end, { unique = true, expr = true })
    end
    for seq in pairs(foldmaps) do
      if vim.fn.maparg(seq) == '' then
        vim.keymap.set({ 'n', 'x' }, seq, function()
          util.invalidate_virtual_line_count_cache(0)
          vim.schedule(view.refresh_bars)
          return seq
        end, { unique = true, expr = true })
      end
    end
  end
end

local did_setup = false

--- @param cfg? SatelliteConfig
function M.setup(cfg)
  if cfg then
    require('satellite.config').apply(cfg)
  end

  if did_setup then
    return
  end

  did_setup = true

  local version = vim.version()
  if version.major == 0 and version.minor < 10 then
    vim.notify('satellite.nvim only supports nvim 0.10 and newer', vim.log.levels.ERROR)
    return
  end

  apply_keymaps()

  api.nvim_create_user_command('SatelliteRefresh', view.refresh_bars, { bar = true, force = true })
  api.nvim_create_user_command('SatelliteEnable', enable, { bar = true, force = true })
  api.nvim_create_user_command('SatelliteDisable', disable, { bar = true, force = true })

  -- The default highlight group is specified below.
  -- Change this default by defining or linking an alternative highlight group.
  -- E.g., the following will use the Pmenu highlight.
  --   :highlight link SatelliteBar Pmenu
  -- E.g., the following will use custom highlight colors.
  --   :highlight SatelliteBar ctermbg=159 guibg=LightCyan
  api.nvim_set_hl(0, 'SatelliteBar', { default = true, link = 'Visual' })

  enable()
end

return M
