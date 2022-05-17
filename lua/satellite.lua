local api = vim.api
local fn = vim.fn

local BUILTIN_HANDLERS = {
  'search',
  'diagnostic',
  'gitsigns',
  'marks',
}

---@class DiagnosticConfig
---@field enable boolean

---@class GitsignsConfig
---@field enable boolean

---@class SearchConfig
---@field enable boolean

---@class HandlerConfigs
---@field diagnostic DiagnosticConfig
---@field gitsigns GitsignsConfig
---@field search SearchConfig

---@class Config
---@field handlers HandlerConfigs
---@field current_only boolean
---@field winblend integer
---@field zindex integer
---@field excluded_filetypes string[]

---@type Config
local user_config = {
  handlers = {
    search = {
      enable = true,
    },
    diagnostic = {
      enable = true,
    },
    gitsigns = {
      enable = true,
    },
    marks = {
      enable = true,
    },
  },
  current_only = false,
  winblend = 50,
  zindex = 40,
  excluded_filetypes = {},
  width = 2,
}

local view_enabled = false

local M = {}

-- Since there is no text displayed in the buffers, the same buffers are used
-- for multiple windows. This also prevents the buffer list from getting high
-- from usage of the plugin.

local winids = {}

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local function round(x)
  return math.floor(x + 0.5)
end

-- Replace termcodes.
local function t(str)
  return api.nvim_replace_termcodes(str, true, true, true)
end

local function is_visual_mode()
  local mode = fn.mode()
  return vim.tbl_contains({'v', 'V', t'<c-v>'}, mode)
end

-- Returns true for ordinary windows (not floating and not external), and false
-- otherwise.
local function is_ordinary_window(winid)
  local config = api.nvim_win_get_config(winid)
  local not_external = not config['external']
  local not_floating = config['relative'] == ''
  return not_external and not_floating
end

-- Return top line and bottom line in window. For folds, the top line
-- represents the start of the fold and the bottom line represents the end of
-- the fold.
local function visible_line_range(winid)
  -- WARN: getwininfo(winid)[1].botline is not properly updated for some
  -- movements (Neovim Issue #13510), so this is implemeneted as a workaround.
  return unpack(api.nvim_win_call(winid, function()
    local topline = fn.line('w0')
    -- line('w$') returns 0 in silent Ex mode, but line('w0') is always greater
    -- than or equal to 1.
    local botline = math.max(fn.line('w$'), topline)
    return {topline, botline}
  end))
end

local function defaulttable()
  return setmetatable({}, {
    __index = function(tbl, k)
      tbl[k] = defaulttable()
      return tbl[k]
    end
  })
end

local virtual_line_count_cache = defaulttable()

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as one
-- virtual line. The computation loops over either lines or virtual spans, so
-- the cursor may be moved.
local function virtual_line_count(winid, start, vend)
  if not vend then
    vend = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
  end

  local cached = rawget(virtual_line_count_cache[winid][start], vend)
  if cached then
    return cached
  end

  return api.nvim_win_call(winid, function()
    local count = 0
    local line = start
    while line <= vend do
      count = count + 1
      local foldclosedend = fn.foldclosedend(line)
      if foldclosedend ~= -1 then
        line = foldclosedend
      end
      line = line + 1
    end
    virtual_line_count_cache[winid][start][vend] = count
    return count
  end)
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual satellite mode, in the current window.
-- The computation primarily loops over lines, but may loop over virtual spans
-- as part of calling 'virtual_line_count', so the cursor may be moved.
local function virtual_topline_lookup()
  local winid = api.nvim_get_current_win()
  local winheight = api.nvim_win_get_height(winid)
  local result = {}  -- A list of line numbers
  local total_vlines = virtual_line_count(winid, 1)
  if total_vlines > 1 and winheight > 1 then
    local count = 1  -- The count of virtual lines
    local line = 1
    local best = line
    local best_distance = math.huge
    local best_count = count
    local bufnr = api.nvim_win_get_buf(winid)
    local last_line = api.nvim_buf_line_count(bufnr)
    for row = 1, winheight do
      local proportion = (row - 1) / (winheight - 1)
      while line <= last_line do
        local current = (count - 1) / (total_vlines - 1)
        local distance = math.abs(current - proportion)
        if distance <= best_distance then
          best = line
          best_distance = distance
          best_count = count
        elseif distance > best_distance then
          -- Prepare variables so that the next row starts iterating at the
          -- current line and count, using an infinite best distance.
          line = best
          best_distance = math.huge
          count = best_count
          break
        end
        local foldclosedend = fn.foldclosedend(line)
        if foldclosedend ~= -1 then
          line = foldclosedend
        end
        line = line + 1
        count = count + 1
      end
      local value = best
      local foldclosed = fn.foldclosed(value)
      if foldclosed ~= -1 then
        value = foldclosed
      end
      table.insert(result, value)
    end
  end
  return result
end

local function row_to_barpos(winid, row)
  local vlinecount0 = virtual_line_count(winid, 1) - 1
  local vrow = virtual_line_count(winid, 1, row)
  local winheight0 = api.nvim_win_get_height(winid) - 1
  return round(winheight0 * vrow / vlinecount0)
end

local ns = api.nvim_create_namespace('satellite')

local function get_symbol(count, s)
  if type(s) == 'string' then
    return s
  end
  local len = #s
  if count > len then
    count = len
  end
  return s[count]
end

local function render_bar(bbufnr, winid, row, height, winheight)
  local lines = {}
  for i = 1, winheight do
    lines[i] = string.rep(' ', user_config.width)
  end

  vim.bo[bbufnr].modifiable = true
  api.nvim_buf_set_lines(bbufnr, 0, -1, true, lines)
  vim.bo[bbufnr].modifiable = false

  local col = user_config.width == 2 and 1 or 0

  for i = row, row+height do
    pcall(api.nvim_buf_set_extmark, bbufnr, ns, i, col, {
      virt_text = { {' ', 'ScrollView'} },
      virt_text_pos = 'overlay',
      priority = 1,
    })
  end

  -- Run handlers
  local bufnr = api.nvim_win_get_buf(winid)
  for _, handler in ipairs(require('satellite.handlers').handlers) do
    local name = handler.name
    local handler_config = user_config.handlers[name]
    if not handler_config or handler_config.enable then
      local positions = {}
      for _, m in ipairs(handler.update(bufnr)) do
        local pos = row_to_barpos(winid, m.lnum-1)
        positions[pos] = (positions[pos] or 0) + 1
        local symbol = get_symbol(positions[pos], m.symbol)

        local mcol = user_config.width == 2 and (m.col or 1) or 0

        local ok, err = pcall(api.nvim_buf_set_extmark, bbufnr, handler.ns, pos, mcol, {
          id = not m.unique and pos+1 or nil,
          virt_text = {{symbol, m.highlight}},
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = positions[pos]
        })
        if not ok then
          print(string.format('%s ROW: %d', handler.name, pos))
          print(err)
        end
      end
    end
  end

end

local function create_view(config)
  local bufnr = api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = 'delete'
  vim.bo[bufnr].buflisted = false

  local winid = api.nvim_open_win(bufnr, false, config)

  local util = require('satellite.util')
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

  local line_count = api.nvim_buf_line_count(bufnr)

  if line_count == 0 then
    return
  end

  -- Don't show the position bar when all lines are on screen.
  local topline, botline = visible_line_range(winid)
  if botline - topline + 1 == line_count then
    return
  end

  -- Invalidate
  virtual_line_count_cache[winid] = nil

  local toprow = row_to_barpos(winid, topline - 1)
  local botrow = row_to_barpos(winid, botline - 1)

  local height = botrow - toprow

  local config = {
    win = winid,
    relative = 'win',
    style = 'minimal',
    focusable = false,
    zindex = user_config.zindex,
    height = winheight,
    width = user_config.width,
    row = 0,
    col = winwidth - user_config.width,
  }

  local bar_winid = winids[winid]
  local bar_bufnr

  if bar_winid and api.nvim_win_is_valid(bar_winid) then
    api.nvim_win_set_config(bar_winid, config)
    bar_bufnr = api.nvim_win_get_buf(bar_winid)
  else
    config.noautocmd = true
    bar_bufnr, bar_winid = create_view(config)
    winids[winid] = bar_winid
  end

  render_bar(bar_bufnr, winid, toprow, height, winheight)

  vim.w[bar_winid].height = height
  vim.w[bar_winid].row = toprow
  vim.w[bar_winid].col = config.col

  return true
end

-- Given a target window row, the corresponding scrollbar is moved to that row.
-- The row is adjusted (up in value, down in visual position) such that the full
-- height of the scrollbar remains on screen.
local function move_scrollbar(winid, row)
  local bar_winid = winids[winid]
  if not bar_winid then
    -- Can happen if mouse is dragged over other floating windows
    return
  end
  local winheight = api.nvim_win_get_height(winid)
  local height = api.nvim_win_get_var(bar_winid, 'height')

  local bar_bufnr0 = api.nvim_win_get_buf(bar_winid)
  render_bar(bar_bufnr0, winid, row, height, winheight)
end

local function noautocmd(f)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = 'all'
  f()
  vim.o.eventignore = eventignore
end

local function close_view_for_win(winid)
  local bar_winid = winids[winid]
  if not api.nvim_win_is_valid(bar_winid) then
    return
  end
  if in_cmdline_win(winid) then
    return
  end
  noautocmd(function()
    api.nvim_win_close(bar_winid, true)
  end)
  winids[winid] = nil
end

-- Get input characters---including mouse clicks and drags---from the input
-- stream. Characters are read until the input stream is empty. Returns a
-- 2-tuple with a string representation of the characters, along with a list of
-- dictionaries that include the following fields:
--   1) char
--   2) str_idx
--   3) charmod
--   4) mouse_winid
--   5) mouse_row
--   6) mouse_col
-- The mouse values are 0 when there was no mouse event or getmousepos is not
-- available. The mouse_winid is set to -1 when a mouse event was on the
-- command line. The mouse_winid is set to -2 when a mouse event was on the
-- tabline.
local function read_input_stream()
  local chars = {}
  local chars_props = {}
  local str_idx = 1  -- in bytes, 1-indexed
  while true do
    local char
    local ok = pcall(function()
      char = fn.getchar()
    end)
    if not ok then
      -- E.g., <c-c>
      char = t'<esc>'
    end
    -- For Vim on Cygwin, pressing <c-c> during getchar() does not raise
    -- "Vim:Interrupt". Handling for such a scenario is added here as a
    -- precaution, by converting to <esc>.
    if char == t'<c-c>' then
      char = t'<esc>'
    end
    local charmod = fn.getcharmod()
    if type(char) == 'number' then
      char = tostring(char)
    end
    table.insert(chars, char)
    local mouse_winid = 0
    local mouse_row = 0
    local mouse_col = 0
    -- Check v:mouse_winid to see if there was a mouse event. Even for clicks
    -- on the command line, where getmousepos().winid could be zero,
    -- v:mousewinid is non-zero.
    if vim.v.mouse_winid ~= 0 then
      mouse_winid = vim.v.mouse_winid
      local mousepos = fn.getmousepos()
      mouse_row = mousepos.winrow
      mouse_col = mousepos.wincol
      -- Handle a mouse event on the command line.
      if mousepos.screenrow > vim.go.lines - vim.go.cmdheight then
        mouse_winid = -1
        mouse_row = mousepos.screenrow - vim.go.lines + vim.go.cmdheight
        mouse_col = mousepos.screencol
      end
      -- Handle a mouse event on the tabline. When the click is on a floating
      -- window covering the tabline, mousepos.winid will be set to that
      -- floating window's winid. Otherwise, mousepos.winid would correspond to
      -- an ordinary window ID (seemingly for the window below the tabline).
      local screenpos = fn.win_screenpos(1)
      if screenpos[1] == 2 and screenpos[2] == 1  -- Checks for presence of a tabline.
          and mousepos.screenrow == 1
          and is_ordinary_window(mousepos.winid) then
        mouse_winid = -2
        mouse_row = mousepos.screenrow
        mouse_col = mousepos.screencol
      end
    end
    local char_props = {
      char = char,
      str_idx = str_idx,
      charmod = charmod,
      mouse_winid = mouse_winid,
      mouse_row = mouse_row,
      mouse_col = mouse_col
    }
    str_idx = str_idx + string.len(char)
    table.insert(chars_props, char_props)
    -- Break if there are no more items on the input stream.
    if fn.getchar(1) == 0 then
      break
    end
  end
  local string = table.concat(chars, '')
  local result = {string, chars_props}
  return unpack(result)
end

-- Scrolls the window so that the specified line number is at the top.
local function set_topline(winid, linenr)
  -- WARN: Unlike other functions that move the cursor (e.g., VirtualLineCount,
  -- VirtualProportionLine), a window workspace should not be used, as the
  -- cursor and viewport changes here are intended to persist.
  api.nvim_win_call(winid, function()
    local init_line = fn.line('.')
    vim.cmd('keepjumps normal! ' .. linenr .. 'G')
    local topline = visible_line_range(winid)
    -- Use virtual lines to figure out how much to scroll up. winline() doesn't
    -- accommodate wrapped lines.
    local virtual_line = virtual_line_count(winid, topline, fn.line('.'))
    if virtual_line > 1 then
      vim.cmd('keepjumps normal! ' .. (virtual_line - 1) .. t'<c-e>')
    end
    local _, botline = visible_line_range(winid)
    if botline == fn.line('$') then
      -- If the last buffer line is on-screen, position that line at the bottom
      -- of the window.
      vim.cmd('keepjumps normal! Gzb')
    end

    -- Position the cursor as if all scrolling was conducted with <ctrl-e> and/or
    -- <ctrl-y>. H and L are used to get topline and botline instead of
    -- getwininfo, to prevent jumping to a line that could result in a scroll if
    -- scrolloff>0.
    vim.cmd('keepjumps normal! H')
    local effective_top = fn.line('.')
    if init_line < effective_top then
      -- User scrolled down.
      return
    end

    vim.cmd('keepjumps normal! L')
    local effective_bottom = fn.line('.')
    if init_line > effective_bottom then
      -- User scrolled up.
      return
    end

    -- The initial line is still on-screen.
    vim.cmd('keepjumps normal! ' .. init_line .. 'G')
  end)
end

-- Returns view properties for the specified window. An empty dictionary
-- is returned if there is no corresponding scrollbar.
local function get_props(winid)
  local bar_winid = winids[winid]
  if not bar_winid then
    return
  end

  return {
    height = vim.w[bar_winid].height,
    row = vim.w[bar_winid].row,
    col = vim.w[bar_winid].col,
  }
end

function M.remove_bars()
  for id, _ in pairs(winids) do
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
      if is_ordinary_window(winid) and api.nvim_win_get_tabpage(winid) == current_tab then
        target_wins[#target_wins+1] = winid
      end
    end
  end
  return target_wins
end

-- Refreshes scrollbars. Global state is initialized and restored.
function M.refresh_bars()
  local current_wins = {}
  for _, winid in ipairs(get_target_windows()) do
    if show_scrollbar(winid) then
      current_wins[#current_wins+1] = winids[winid]
    end
  end

  -- Close any remaining bars
  for winid, swinid in pairs(winids) do
    if not vim.tbl_contains(current_wins, swinid) then
      close_view_for_win(winid)
    end
  end
end

local function enable()
  view_enabled = true

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
  view_enabled = false
  api.nvim_create_augroup('satellite', {})
  M.remove_bars()
end

local function refresh()
  if view_enabled then
    M.refresh_bars()
  end
end

local MOUSEDOWN = t('<leftmouse>')
local MOUSEUP = t('<leftrelease>')

local function handle_leftmouse()
  -- Re-send the click, so its position can be obtained through
  -- read_input_stream().
  fn.feedkeys(MOUSEDOWN, 'ni')
  if not view_enabled then
    -- disabled. Process the click as it would ordinarily be
    -- processed
    return
  end
  local count = 0
  local winid  -- The target window ID for a mouse scroll.
  local bufnr  -- The target buffer number.
  local scrollbar_offset
  local previous_row
  local idx = 1
  local string, chars_props = '', {}
  local str_idx, char, mouse_winid, mouse_row, mouse_col
  -- Computing this prior to the first mouse event could distort the location
  -- since this could be an expensive operation (and the mouse could move).
  local the_topline_lookup
  while true do
    while true do
      idx = idx + 1
      if idx > #chars_props then
        idx = 1
        string, chars_props = read_input_stream()
      end
      local char_props = chars_props[idx]
      str_idx = char_props.str_idx
      char = char_props.char
      mouse_winid = char_props.mouse_winid
      mouse_row = char_props.mouse_row
      mouse_col = char_props.mouse_col
      -- Break unless it's a mouse drag followed by another mouse drag, so
      -- that the first drag is skipped.
      if mouse_winid == 0
          or vim.tbl_contains({MOUSEDOWN, MOUSEUP}, char) then
        break
      end
      if idx >= #char_props then break end
      local next = chars_props[idx + 1]
      if next.mouse_winid == 0
          or vim.tbl_contains({MOUSEDOWN, MOUSEUP}, next.char) then
        break
      end
    end

    if char == t'<esc>' then
      fn.feedkeys(string.sub(string, str_idx + #char), 'ni')
      return
    end

    -- In select-mode, mouse usage results in the mode intermediately
    -- switching to visual mode, accompanied by a call to this function.
    -- After the initial mouse event, the next getchar() character is
    -- <80><f5>X. This is "Used for switching Select mode back on after a
    -- mapping or menu" (https://github.com/vim/vim/blob/
    -- c54f347d63bcca97ead673d01ac6b59914bb04e5/src/keymap.h#L84-L88,
    -- https://github.com/vim/vim/blob/
    -- c54f347d63bcca97ead673d01ac6b59914bb04e5/src/getchar.c#L2660-L2672)
    -- Ignore this character after scrolling has started.
    -- NOTE: "\x80\xf5X" (hex) ==# "\200\365X" (octal)
    if not (char == '\x80\xf5X' and count > 0) then
      if mouse_winid == 0 then
        -- There was no mouse event.
        fn.feedkeys(string.sub(string, str_idx), 'ni')
        return
      end

      if char == MOUSEUP then
        if count == 0 then
          -- No initial MOUSEDOWN was captured.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
        elseif count == 1 then
          -- A scrollbar was clicked, but there was no corresponding drag.
          -- Allow the interaction to be processed as it would be with no
          -- scrollbar.
          fn.feedkeys(MOUSEDOWN .. string.sub(string, str_idx), 'ni')
        else
          -- A scrollbar was clicked and there was a corresponding drag.
          -- 'feedkeys' is not called, since the full mouse interaction has
          -- already been processed. The current window (from prior to
          -- scrolling) is not changed.
          M.refresh_bars()
        end
        return
      end

      if count == 0 then
        if mouse_winid < 0 then
          -- The mouse event was on the tabline or command line.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end

        local props = get_props(mouse_winid)
        if not props then
          return
        end

        -- Add 1 cell horizontal left-padding for grabbing the scrollbar. Don't
        -- add right-padding as this would extend past the window and will
        -- interfere with dragging the vertical separator to resize the window.
        if mouse_row < props.row
            or mouse_row >= props.row + props.height
            or mouse_col < props.col
            or mouse_col > props.col + 1 then
          -- The click was not on a scrollbar.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end

        -- The click was on a scrollbar.
        -- Refresh the scrollbars and check if the mouse is still over a
        -- scrollbar. If not, ignore all mouse events until a MOUSEUP. This
        -- approach was deemed preferable to refreshing scrollbars initially, as
        -- that could result in unintended clicking/dragging where there is no
        -- scrollbar.
        M.refresh_bars()

        -- Don't restore toplines whenever a scrollbar was clicked. This
        -- prevents the window where a scrollbar is dragged from having its
        -- topline restored to the pre-drag position. This also prevents
        -- restoring windows that may have had their windows shifted during the
        -- course of scrollbar clicking/dragging, to prevent jumpiness in the
        -- display.
        props = get_props(mouse_winid)
        if not props then
          return
        end

        if mouse_row < props.row
            or mouse_row >= props.row + props.height then
          while fn.getchar() ~= MOUSEUP do end
          return
        end

        -- By this point, the click on a scrollbar was successful.
        if is_visual_mode() then
          -- Exit visual mode.
          vim.cmd('normal! ' .. t'<esc>')
        end
        winid = mouse_winid
        bufnr = api.nvim_win_get_buf(winid)
        scrollbar_offset = props.row - mouse_row
        previous_row = props.row
      end
      -- Only consider a scrollbar update for mouse events on windows (i.e.,
      -- not on the tabline or command line).
      if mouse_winid > 0 then
        local winheight = api.nvim_win_get_height(winid)
        local mouse_winrow = fn.getwininfo(mouse_winid)[1].winrow
        local winrow = fn.getwininfo(winid)[1].winrow
        local window_offset = mouse_winrow - winrow
        local row = mouse_row + window_offset + scrollbar_offset
        local props = get_props(winid)
        if not props then
          return
        end
        row = math.max(1, math.min(row, winheight - props.height + 1))
        -- Only update scrollbar if the row changed.
        if previous_row ~= row then
          local topline
          if row == 1 then
            -- If the scrollbar was dragged to the top of the window, always show
            -- the first line.
            topline = 1
          elseif row + props.height - 1 >= winheight then
            -- If the scrollbar was dragged to the bottom of the window, always
            -- show the bottom line.
            topline = api.nvim_buf_line_count(bufnr)
          else
            if not the_topline_lookup then
              the_topline_lookup = api.nvim_win_call(winid, virtual_topline_lookup)
            end
            topline = math.max(1, the_topline_lookup[row])
          end
          set_topline(winid, topline)
          if vim.wo[winid].scrollbind or vim.wo[winid].cursorbind then
            M.refresh_bars()
          end
          move_scrollbar(mouse_winid, row)
          previous_row = row
        end
      end
      count = count + 1
    end  -- end while
  end  -- end while
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
  refresh()
end

local function apply_keymaps()
  -- === Fold command synchronization workarounds ===
  -- zf takes a motion in normal mode, so it requires a g@ mapping.
  vim.keymap.set('n', 'zf', function()
    vim.o.operatorfunc = 'v:lua:package.loaded.satellite.zf_operator'
    return 'g@'
  end, {unique = true})

  for _, seq in ipairs{
    'zF', 'zd', 'zD', 'zE', 'zo', 'zO', 'zc', 'zC', 'za', 'zA', 'zv',
    'zx', 'zX', 'zm', 'zM', 'zr', 'zR', 'zn', 'zN', 'zi'
  } do
    vim.keymap.set({'n', 'v'}, seq, function()
      vim.schedule(refresh)
      return seq
    end, {unique = true, expr=true})
  end

  vim.keymap.set({'n', 'v', 'o', 'i'}, '<leftmouse>', handle_leftmouse)
end

function M.setup(config)
  user_config = vim.tbl_extend('force', user_config, config or {})

  -- Load builtin handlers
  for _, name in ipairs(BUILTIN_HANDLERS) do
    if user_config.handlers[name].enable then
      require('satellite.handlers.'..name)
    end
  end

  apply_keymaps()

  api.nvim_create_user_command('SatelliteRefresh', refresh, {bar = true, force = true})
  api.nvim_create_user_command('SatelliteEnable' , enable , {bar = true, force = true})
  api.nvim_create_user_command('SatelliteDisable', disable, {bar = true, force = true})

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
