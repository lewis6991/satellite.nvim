local api = vim.api
local fn = vim.fn

local scrollview_enabled = false
local scrollview_zindex = 40
local scrollview_winblend = 50
local scrollview_excluded_filetypes = {}
local scrollview_current_only = false

-- Since there is no text displayed in the buffers, the same buffers are used
-- for multiple windows. This also prevents the buffer list from getting high
-- from usage of the plugin.

-- bar_bufnr has the bufnr of the buffer created for a position bar.
local bar_bufnr = -1

local sv_winids = {}

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local round = function(x)
  return math.floor(x + 0.5)
end

-- Replace termcodes.
local t = function(str)
  return api.nvim_replace_termcodes(str, true, true, true)
end

-- Get value from a map-like table, using the specified default.
local tbl_get = function(table, key, default)
  local result = table[key]
  if result == nil then
    result = default
  end
  return result
end

-- Returns true for boolean true and any non-zero number, otherwise returns
-- false.
local to_bool = function(x)
  if type(x) == 'boolean' then
    return x
  elseif type(x) == 'number' then
    return x ~= 0
  end
  return false
end

-- *************************************************
-- * Core
-- *************************************************

local is_visual_mode = function(mode)
  return vim.tbl_contains({'v', 'V', t'<c-v>'}, mode)
end

-- Returns true for ordinary windows (not floating and not external), and false
-- otherwise.
local is_ordinary_window = function(winid)
  local config = api.nvim_win_get_config(winid)
  local not_external = not tbl_get(config, 'external', false)
  local not_floating = tbl_get(config, 'relative', '') == ''
  return not_external and not_floating
end

-- Returns a list of window IDs for the ordinary windows.
local get_ordinary_windows = function()
  local winids = {}
  for _, winid in ipairs(api.nvim_list_wins()) do
    if is_ordinary_window(winid) then
      table.insert(winids, winid)
    end
  end
  return winids
end

local in_command_line_window = function()
  if fn.win_gettype() == 'command' then
    return true
  end
  if api.nvim_get_mode().mode == 'c' then
    return true
  end
  local bufnr = api.nvim_get_current_buf()
  local buftype = vim.bo[bufnr].buftype
  local bufname = api.nvim_buf_get_name(bufnr)
  return buftype == 'nofile' and bufname == '[Command Line]'
end

-- Return top line and bottom line in window. For folds, the top line
-- represents the start of the fold and the bottom line represents the end of
-- the fold.
local line_range = function(winid)
  -- WARN: getwininfo(winid)[1].botline is not properly updated for some
  -- movements (Neovim Issue #13510), so this is implemeneted as a workaround.
  -- Using scrolloff=0 combined with H and L breaks diff mode. Scrolling is not
  -- possible and/or the window scrolls when it shouldn't. Temporarily turning
  -- off scrollbind and cursorbind accommodates, but the following is simpler.
  return unpack(api.nvim_win_call(winid, function()
    local topline = fn.line('w0')
    -- line('w$') returns 0 in silent Ex mode, but line('w0') is always greater
    -- than or equal to 1.
    local botline = math.max(fn.line('w$'), topline)
    return {topline, botline}
  end))
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as one
-- virtual line. The computation loops over either lines or virtual spans, so
-- the cursor may be moved.
local virtual_line_count = function(winid, start, _end)
  if type(_end) == 'string' and _end == '$' then
    _end = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
  end
  return api.nvim_win_call(winid, function()
    local count = 0
    local line = start
    while line <= _end do
      count = count + 1
      local foldclosedend = fn.foldclosedend(line)
      if foldclosedend ~= -1 then
        line = foldclosedend
      end
      line = line + 1
    end
    return count
  end)
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation primarily loops over lines, but may loop over virtual spans
-- as part of calling 'virtual_line_count', so the cursor may be moved.
local virtual_topline_lookup_linewise = function()
  local winid = api.nvim_get_current_win()
  local winheight = api.nvim_win_get_height(winid)
  local result = {}  -- A list of line numbers
  local total_vlines = virtual_line_count(winid, 1, '$')
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

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode. The computation loops
-- over either lines or virtual spans, so the cursor may be moved.
local virtual_topline_lookup = function(winid)
  return api.nvim_win_call(winid, virtual_topline_lookup_linewise)
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row.
local topline_lookup = function(winid)
  local topline_lookup = {}
  -- Handling for virtual mode or an unknown mode.
  for _, x in ipairs(virtual_topline_lookup(winid)) do
    table.insert(topline_lookup, x)
  end
  return topline_lookup
end

-- Calculates the bar position for the specified window. Returns a dictionary
-- with a height, row, and col.
local calculate_position = function(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local topline, botline = line_range(winid)
  local line_count = api.nvim_buf_line_count(bufnr)
  -- For virtual mode or an unknown mode, update effective_topline and
  -- effective_line_count to correspond to virtual lines, which account for
  -- closed folds.
  local effective_topline = virtual_line_count(winid, 1, topline - 1) + 1
  local effective_line_count = virtual_line_count(winid, 1, '$')
  local winheight = api.nvim_win_get_height(winid)
  local winwidth = api.nvim_win_get_width(winid)
  -- top is the position for the top of the scrollbar, relative to the window,
  -- and 0-indexed.
  local top = 0
  if effective_line_count > 1 then
    top = (effective_topline - 1) / (effective_line_count - 1)
    top = round((winheight - 1) * top)
  end
  local height = winheight
  if effective_line_count > height then
    height = winheight / effective_line_count
    height = math.ceil(height * winheight)
    height = math.max(1, height)
  end
  -- Make sure bar properly reflects bottom of document.
  if botline == line_count then
    top = winheight - height
  end
  -- Make sure bar never overlaps status line.
  if top + height > winheight then
    top = winheight - height
  end
  return {
    height = height,
    row = top + 1,
    col = winwidth
  }
end

local is_scrollview_window = function(winid)
  if is_ordinary_window(winid) then
    return false
  end
  local has_attr = false
  pcall(function()
    has_attr = api.nvim_win_get_var(winid, 'scrollview_key') == 'scrollview_val'
  end)
  if not has_attr then
    return false
  end
  local bufnr = api.nvim_win_get_buf(winid)
  return bufnr == bar_bufnr
end

-- Show a scrollbar for the specified 'winid' window ID, using the specified
-- 'bar_winid' floating window ID (a new floating window will be created if
-- this is -1). Returns -1 if the bar is not shown, and the floating window ID
-- otherwise.
local show_scrollbar = function(winid, bar_winid)
  local winnr = api.nvim_win_get_number(winid)
  local bufnr = api.nvim_win_get_buf(winid)
  local buf_filetype = api.nvim_buf_get_option(bufnr, 'filetype')
  local winheight = fn.winheight(winnr)
  local winwidth = fn.winwidth(winnr)
  local wininfo = fn.getwininfo(winid)[1]
  -- Skip if the filetype is on the list of exclusions.
  if vim.tbl_contains(scrollview_excluded_filetypes, buf_filetype) then
    return -1
  end
  -- Don't show in terminal mode, since the bar won't be properly updated for
  -- insertions.
  if to_bool(wininfo.terminal) then
    return -1
  end
  if winheight == 0 or winwidth == 0 then
    return -1
  end
  local line_count = api.nvim_buf_line_count(bufnr)
  -- Don't show the position bar when all lines are on screen.
  local topline, botline = line_range(winid)
  if botline - topline + 1 == line_count then
    return -1
  end
  local bar_position = calculate_position(winid)
  -- Height has to be positive for the call to nvim_open_win. When opening a
  -- terminal, the topline and botline can be set such that height is negative
  -- when you're using scrollview document mode.
  if bar_position.height <= 0 then
    return -1
  end
  -- Don't show scrollbar when its column is beyond what's valid.
  local min_valid_col = 1
  local max_valid_col = winwidth
  if bar_position.col < min_valid_col then
    return -1
  end
  if bar_position.col > max_valid_col then
    return -1
  end
  if bar_bufnr == -1 or not fn.bufexists(bar_bufnr) then
    bar_bufnr = api.nvim_create_buf(false, true)
    vim.bo[bar_bufnr].modifiable = false
    vim.bo[bar_bufnr].filetype = 'scrollview'
    vim.bo[bar_bufnr].buftype = 'nofile'
    vim.bo[bar_bufnr].swapfile = false
    vim.bo[bar_bufnr].bufhidden = 'hide'
    vim.bo[bar_bufnr].buflisted = false
  end
  -- Make sure that a custom character is up-to-date and is repeated enough to
  -- cover the full height of the scrollbar.
  local bar_line_count = api.nvim_buf_line_count(bar_bufnr)
  if api.nvim_buf_get_lines(bar_bufnr, 0, 1, false)[1] ~= vim.g.scrollview_character
      or bar_position.height > bar_line_count then
    vim.bo[bar_bufnr].modifiable = true
    api.nvim_buf_set_lines(
      bar_bufnr, 0, bar_line_count, false,
      fn['repeat']({vim.g.scrollview_character}, bar_position.height))
    vim.bo[bar_bufnr].modifiable = false
  end

  local config = {
    win = winid,
    relative = 'win',
    focusable = false,
    style = 'minimal',
    height = bar_position.height,
    width = 1,
    row = bar_position.row - 1,
    col = bar_position.col - 1,
    zindex = scrollview_zindex
  }
  if bar_winid then
    api.nvim_win_set_config(bar_winid, config)
  else
    bar_winid = api.nvim_open_win(bar_bufnr, false, config)
    sv_winids[#sv_winids+1] = bar_winid
  end
  -- Scroll to top so that the custom character spans full scrollbar height.
  vim.cmd('keepjumps call nvim_win_set_cursor(' .. bar_winid .. ', [1, 0])')
  -- It's not sufficient to just specify Normal highlighting. With just that, a
  -- color scheme's specification of EndOfBuffer would be used to color the
  -- bottom of the scrollbar.
  vim.wo[bar_winid].winhighlight = 'Normal:ScrollView,EndOfBuffer:ScrollView'
  vim.wo[bar_winid].winblend = scrollview_winblend
  vim.wo[bar_winid].foldcolumn = '0'  -- foldcolumn takes a string
  vim.wo[bar_winid].wrap = false
  api.nvim_win_set_var(bar_winid, 'scrollview_key', 'scrollview_val')
  api.nvim_win_set_var(bar_winid, 'scrollview_props', {
    parent_winid = winid,
    scrollview_winid = bar_winid,
    height = bar_position.height,
    row = bar_position.row,
    col = bar_position.col
  })
  return bar_winid
end

-- Given a scrollbar properties dictionary and a target window row, the
-- corresponding scrollbar is moved to that row. The row is adjusted (up in
-- value, down in visual position) such that the full height of the scrollbar
-- remains on screen. Returns the updated scrollbar properties.
local move_scrollbar = function(props, row)
  props = vim.deepcopy(props)
  local max_row = fn.winheight(props.parent_winid) - props.height + 1
  row = math.min(row, max_row)
  local options = {
    win = props.parent_winid,
    relative = 'win',
    row = row - 1,
    col = props.col - 1
  }
  api.nvim_win_set_config(props.scrollview_winid, options)
  props.row = row
  api.nvim_win_set_var(props.scrollview_winid, 'scrollview_props', props)
  return props
end

local get_scrollview_windows = function()
  local result = {}
  for _, winid in ipairs(api.nvim_list_wins()) do
    if is_scrollview_window(winid) then
      table.insert(result, winid)
    end
  end
  return result
end

local close_scrollview_window = function(winid)
  -- The floating window may have been closed (e.g., :only/<ctrl-w>o, or
  -- intentionally deleted prior to the removal callback in order to reduce
  -- motion blur).
  if not api.nvim_win_is_valid(winid) then
    return
  end
  if not is_scrollview_window(winid) then
    return
  end
  local eventignore = vim.o.eventignore
  vim.o.eventignore = 'all'
  api.nvim_win_close(winid, true)
  vim.o.eventignore = eventignore
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
local read_input_stream = function()
  local chars = {}
  local chars_props = {}
  local str_idx = 1  -- in bytes, 1-indexed
  while true do
    local char
    if not pcall(function()
      char = fn.getchar()
    end) then
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
    if vim.v.mouse_winid ~= 0 and to_bool(fn.exists('*getmousepos')) then
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
      if fn.win_screenpos(1) == {2, 1}  -- Checks for presence of a tabline.
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
local set_topline = function(winid, linenr)
  -- WARN: Unlike other functions that move the cursor (e.g., VirtualLineCount,
  -- VirtualProportionLine), a window workspace should not be used, as the
  -- cursor and viewport changes here are intended to persist.
  api.nvim_win_call(winid, function()
    local init_line = fn.line('.')
    vim.cmd('keepjumps normal! ' .. linenr .. 'G')
    local topline = line_range(winid)
    -- Use virtual lines to figure out how much to scroll up. winline() doesn't
    -- accommodate wrapped lines.
    local virtual_line = virtual_line_count(winid, topline, fn.line('.'))
    if virtual_line > 1 then
      vim.cmd('keepjumps normal! ' .. (virtual_line - 1) .. t'<c-e>')
    end
    -- Make sure 'topline' is correct, as a precaution.
    topline = nil  -- luacheck: no unused
    local _, botline = line_range(winid)
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
    vim.cmd('keepjumps normal! L')
    local effective_bottom = fn.line('.')
    if init_line < effective_top then
      -- User scrolled down.
      vim.cmd('keepjumps normal! H')
    elseif init_line > effective_bottom then
      -- User scrolled up.
      vim.cmd('keepjumps normal! L')
    else
      -- The initial line is still on-screen.
      vim.cmd('keepjumps normal! ' .. init_line .. 'G')
    end
  end)
end

-- Returns scrollview properties for the specified window. An empty dictionary
-- is returned if there is no corresponding scrollbar.
local get_scrollview_props = function(winid)
  for _, swinid in ipairs(api.nvim_list_wins()) do
    local props = vim.w[swinid].scrollview_props
    if props and props.parent_winid == winid then
      return props
    end
  end
  return {}
end

-- With no argument, remove all bars. Otherwise, remove the specified list of
-- bars. Global state is initialized and restored.
local remove_bars = function(target_wins)
  if bar_bufnr == -1 then
    return
  end
  target_wins = target_wins or api.nvim_list_wins()
  for _, winid in ipairs(target_wins) do
    close_scrollview_window(winid)
  end
end

-- Remove scrollbars if InCommandLineWindow is true. This fails when called
-- from the CmdwinEnter event (some functionality, like nvim_win_close, cannot
-- be used from the command line window), but works during the transition to
-- the command line window (from the WinEnter event).
local remove_if_command_line_window = function()
  if in_command_line_window() then
    pcall(remove_bars)
  end
end

-- Refreshes scrollbars. Global state is initialized and restored.
local refresh_bars = function()
  if in_command_line_window() then
    return
  end

  -- Existing windows are determined before adding new windows, but removed
  -- later (they have to be removed after adding to prevent flickering from
  -- the delay between removal and adding).
  local existing_wins = get_scrollview_windows()
  local target_wins

  if scrollview_current_only then
    target_wins = { api.nvim_get_current_win() }
  else
    target_wins = {}
    for _, winid in ipairs(get_ordinary_windows()) do
      table.insert(target_wins, winid)
    end
  end

  for _, winid in ipairs(target_wins) do
    -- Reuse an existing scrollbar floating window when available. This
    -- prevents flickering when there are folds. This keeps the window IDs
    -- smaller than they would be otherwise. The benefits of small window
    -- IDs seems relatively less beneficial than small buffer numbers,
    -- since they would ordinarily be used less as inputs to commands
    -- (where smaller numbers are preferable for their fewer digits to
    -- type).
    local existing_winid = existing_wins[#existing_wins]
    local bar_winid = show_scrollbar(winid, existing_winid)
    -- If an existing window was successfully reused, remove it from the
    -- existing window list.
    if bar_winid ~= -1 and existing_winid ~= -1 then
      table.remove(existing_wins)
    end
  end
  for _, winid in ipairs(existing_wins) do
    close_scrollview_window(winid)
  end
end

-- *************************************************
-- * Main (entry points)
-- *************************************************

local scrollview_enable = function()
  scrollview_enabled = true
  vim.cmd([[
    augroup scrollview
      autocmd!
      " === Scrollbar Removal ===

      " For the duration of command-line window usage, there should be no bars.
      " Without this, bars can possibly overlap the command line window. This
      " can be problematic particularly when there is a vertical split with the
      " left window's bar on the bottom of the screen, where it would overlap
      " with the center of the command line window. It was not possible to use
      " CmdwinEnter, since the removal has to occur prior to that event. Rather,
      " this is triggered by the WinEnter event, just prior to the relevant
      " funcionality becoming unavailable.
      autocmd WinEnter * :lua require('scrollview').remove_if_command_line_window()
      " The following error can arise when the last window in a tab is going to
      " be closed, but there are still open floating windows, and at least one
      " other tab.
      "   > "E5601: Cannot close window, only floating window would remain"
      " Neovim Issue #11440 is open to address this. As of 2020/12/12, this
      " issue is a 0.6 milestone.
      " The autocmd below removes bars subsequent to :quit, :wq, or :qall (and
      " also ZZ and ZQ), to avoid the error. However, the error will still arise
      " when <ctrl-w>c or :close are used. To avoid the error in those cases,
      " <ctrl-w>o can be used to first close the floating windows, or
      " alternatively :tabclose can be used (or one of the alternatives handled
      " with the autocmd, like ZQ).
      autocmd QuitPre * :lua require('scrollview').remove_bars()

      " === Scrollbar Refreshing ===

      " The following handles bar refreshing when changing the current window.
      autocmd WinEnter,TermEnter * :lua require('scrollview').refresh_bars()
      " The following restores bars after leaving the command-line window.
      " Refreshing must be asynchronous, since the command line window is still
      " in an intermediate state when the CmdwinLeave event is triggered.
      autocmd CmdwinLeave * :lua require('scrollview').refresh_bars()
      " The following handles scrolling events, which could arise from various
      " actions, including resizing windows, movements (e.g., j, k), or
      " scrolling (e.g., <ctrl-e>, zz).
      autocmd WinScrolled * :lua require('scrollview').refresh_bars()
      " The following handles the case where text is pasted. TextChangedI is not
      " necessary since WinScrolled will be triggered if there is corresponding
      " scrolling.
      autocmd TextChanged * :lua require('scrollview').refresh_bars()
      " The following handles when :e is used to load a file.
      autocmd BufWinEnter * :lua require('scrollview').refresh_bars()
      " The following is used so that bars are shown when cycling through tabs.
      autocmd TabEnter * :lua require('scrollview').refresh_bars()
      autocmd VimResized * :lua require('scrollview').refresh_bars()
    augroup END
  ]])
  refresh_bars()
end

local scrollview_disable = function()
  local winid = api.nvim_get_current_win()
  pcall(function()
    if in_command_line_window() then
      vim.cmd([[
        echohl ErrorMsg
        echo 'nvim-scrollview: Cannot disable from command-line window'
        echohl None
      ]])
      return
    end
    scrollview_enabled = false
    vim.cmd([[
      augroup scrollview
        autocmd!
      augroup END
    ]])
    remove_bars()
  end)
  api.nvim_set_current_win(winid)
end

local scrollview_refresh = function()
  if scrollview_enabled then
    refresh_bars()
  end
end

-- 'button' can be 'left', 'middle', 'right', 'x1', or 'x2'.
local handle_mouse = function(button)
  if not vim.tbl_contains({'left', 'middle', 'right', 'x1', 'x2'}, button) then
    error('Unsupported button: ' .. button)
  end
  local mousedown = t('<' .. button .. 'mouse>')
  local mouseup = t('<' .. button .. 'release>')
  if not scrollview_enabled then
    -- nvim-scrollview is disabled. Process the click as it would ordinarily be
    -- processed, by re-sending the click and returning.
    fn.feedkeys(mousedown, 'ni')
    return
  end
  pcall(function()
    -- Re-send the click, so its position can be obtained through
    -- read_input_stream().
    fn.feedkeys(mousedown, 'ni')
    -- Mouse handling is not relevant in the command line window since
    -- scrollbars are not shown. Additionally, the overlay cannot be closed
    -- from that mode.
    if in_command_line_window() then
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
    local props
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
            or vim.tbl_contains({mousedown, mouseup}, char) then
          break
        end
        if idx >= #char_props then break end
        local next = chars_props[idx + 1]
        if next.mouse_winid == 0
            or vim.tbl_contains({mousedown, mouseup}, next.char) then
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
      if char == '\x80\xf5X' and count > 0 then
        goto continue
      end
      if mouse_winid == 0 then
        -- There was no mouse event.
        fn.feedkeys(string.sub(string, str_idx), 'ni')
        return
      end
      if char == mouseup then
        if count == 0 then
          -- No initial mousedown was captured.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
        elseif count == 1 then
          -- A scrollbar was clicked, but there was no corresponding drag.
          -- Allow the interaction to be processed as it would be with no
          -- scrollbar.
          fn.feedkeys(mousedown .. string.sub(string, str_idx), 'ni')
        else
          -- A scrollbar was clicked and there was a corresponding drag.
          -- 'feedkeys' is not called, since the full mouse interaction has
          -- already been processed. The current window (from prior to
          -- scrolling) is not changed.
          refresh_bars()
        end
        return
      end
      if count == 0 then
        if mouse_winid < 0 then
          -- The mouse event was on the tabline or command line.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end
        props = get_scrollview_props(mouse_winid)
        if vim.tbl_isempty(props) then
          -- There was no scrollbar in the window where a click occurred.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end
        -- Add 1 cell horizonal padding for grabbing the scrollbar. Don't do
        -- this when the padding would extend past the window, as it will
        -- interfere with dragging the vertical separator to resize the window.
        local lpad = 0
        if props.col > 1 then
          lpad = 1
        end
        local rpad = 0
        if props.col < api.nvim_win_get_width(mouse_winid) then
          rpad = 1
        end
        if mouse_row < props.row
            or mouse_row >= props.row + props.height
            or mouse_col < props.col - lpad
            or mouse_col > props.col + rpad then
          -- The click was not on a scrollbar.
          fn.feedkeys(string.sub(string, str_idx), 'ni')
          return
        end
        -- The click was on a scrollbar.
        -- It's possible that the clicked scrollbar is out-of-sync. Refresh the
        -- scrollbars and check if the mouse is still over a scrollbar. If not,
        -- ignore all mouse events until a mouseup. This approach was deemed
        -- preferable to refreshing scrollbars initially, as that could result
        -- in unintended clicking/dragging where there is no scrollbar.
        refresh_bars()
        -- Redraw to refresh the buffer if the scrollbar is being dragged
        vim.cmd('redraw')
        -- Don't restore toplines whenever a scrollbar was clicked. This
        -- prevents the window where a scrollbar is dragged from having its
        -- topline restored to the pre-drag position. This also prevents
        -- restoring windows that may have had their windows shifted during the
        -- course of scrollbar clicking/dragging, to prevent jumpiness in the
        -- display.
        props = get_scrollview_props(mouse_winid)
        if vim.tbl_isempty(props) or mouse_row < props.row
            or mouse_row >= props.row + props.height then
          while fn.getchar() ~= mouseup do end
          return
        end
        -- By this point, the click on a scrollbar was successful.
        if is_visual_mode(fn.mode()) then
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
        row = math.min(row, winheight - props.height + 1)
        row = math.max(1, row)
        -- Only update scrollbar if the row changed.
        if previous_row ~= row then
          if the_topline_lookup == nil then
            the_topline_lookup = topline_lookup(winid)
          end
          local topline = math.max(1, the_topline_lookup[row])
          if row == 1 then
            -- If the scrollbar was dragged to the top of the window, always show
            -- the first line.
            topline = 1
          elseif row + props.height - 1 >= winheight then
            -- If the scrollbar was dragged to the bottom of the window, always
            -- show the bottom line.
            topline = api.nvim_buf_line_count(bufnr)
          end
          set_topline(winid, topline)
          if vim.wo[winid].scrollbind or vim.wo[winid].cursorbind then
            refresh_bars()
            props = get_scrollview_props(winid)
          end
          props = move_scrollbar(props, row)
          vim.cmd('redraw')
          previous_row = row
        end
      end
      count = count + 1
      ::continue::
    end  -- end while
  end)  -- end pcall
end

return {
  -- Functions called internally (by autocmds).
  refresh_bars = refresh_bars,
  remove_bars = remove_bars,
  remove_if_command_line_window = remove_if_command_line_window,

  -- Functions called by commands and mappings defined in
  -- plugin/scrollview.vim.
  scrollview_enable = scrollview_enable,
  scrollview_disable = scrollview_disable,
  scrollview_refresh = scrollview_refresh,
  handle_mouse = handle_mouse,
}
