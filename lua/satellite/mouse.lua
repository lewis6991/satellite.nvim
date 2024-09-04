local fn, api = vim.fn, vim.api

local util = require 'satellite.util'
local view = require 'satellite.view'

local t = vim.keycode

local LEFTMOUSE = t '<leftmouse>'
local LEFTRELEASE = t '<leftrelease>'

local function get_topline(winid, bufnr, row, bar_height)
  if row == 0 then
    -- If the scrollbar was dragged to the top of the window, always show
    -- the first line.
    return 1
  end

  local winheight = util.get_winheight(winid)
  if row + bar_height >= winheight then
    -- If the scrollbar was dragged to the bottom of the window, always
    -- show the bottom line.
    return api.nvim_buf_line_count(bufnr)
  end

  return math.max(1, util.virtual_topline_lookup(winid)[row])
end

--- Scrolls the window so that the specified line number is at the top.
--- @param winid integer
--- @param linenr integer
local function set_topline(winid, linenr)
  api.nvim_win_call(winid, function()
    local init_line = fn.line('.')
    vim.cmd('keepjumps normal! ' .. linenr .. 'G')
    local topline = util.visible_line_range(winid)
    -- Use virtual lines to figure out how much to scroll up. winline() doesn't
    -- accommodate wrapped lines.
    local virtual_line = util.virtual_line_count(winid, topline, fn.line('.'))
    if virtual_line > 1 then
      vim.cmd('keepjumps normal! ' .. (virtual_line - 1) .. t '<c-e>')
    end
    local _, botline = util.visible_line_range(winid)
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

--- @return string
local function getchar()
  local ok, char0 = pcall(fn.getchar)
  local char = ok and tostring(char0) or t '<esc>'
  -- For Vim on Cygwin, pressing <c-c> during getchar() does not raise
  -- "Vim:Interrupt". Handling for such a scenario is added here as a
  -- precaution, by converting to <esc>.
  if char == t '<c-c>' then
    char = t '<esc>'
  end
  return char
end

--- Get input characters---including mouse clicks and drags---from the input
--- stream. Characters are read until the input stream is empty.
---
--- The mouse values are 0 when there was no mouse event. The winid is set to
--- -1 when a mouse event was on the command line. The winid is set to -2 when
--- a mouse event was on the tabline.
--- @return string characters
--- @return Satellite.Mouse.Props[] props
local function read_input_stream()
  local chars = {} --- @type string[]
  local chars_props = {} --- @type Satellite.Mouse.Props[]
  local str_idx = 1 -- in bytes, 1-indexed
  while true do
    local char = getchar()
    chars[#chars + 1] = char

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
      if
        screenpos[1] == 2
        and screenpos[2] == 1 -- Checks for presence of a tabline.
        and mousepos.screenrow == 1
        and util.is_ordinary_window(mousepos.winid)
      then
        mouse_winid = -2
        mouse_row = mousepos.screenrow
        mouse_col = mousepos.screencol
      end
    end

    chars_props[#chars_props + 1] = {
      char = char,
      str_idx = str_idx,
      winid = mouse_winid,
      row = mouse_row,
      col = mouse_col,
    }

    str_idx = str_idx + char:len()

    -- Break if there are no more items on the input stream.
    if fn.getchar(1) == 0 then
      break
    end
  end

  return table.concat(chars, ''), chars_props
end

--- @param winid integer
--- @return integer
local function get_winrow(winid)
  return fn.getwininfo(winid)[1].winrow --- @type integer
end

local M = {}

--- @param count integer
--- @param char string
local function handle_leftrelease(count, char)
  if count == 0 then
    -- No initial MOUSEDOWN was captured.
    api.nvim_feedkeys(char, 'ni', false)
  elseif count == 1 then
    -- A scrollbar was clicked, but there was no corresponding drag.
    -- Allow the interaction to be processed as it would be with no
    -- scrollbar.
    api.nvim_feedkeys(LEFTMOUSE .. char, 'ni', false)
  else
    -- A scrollbar was clicked and there was a corresponding drag.
    -- 'feedkeys' is not called, since the full mouse interaction has
    -- already been processed. The current window (from prior to
    -- scrolling) is not changed.
    view.refresh_bars()
  end
end

--- @class Satellite.Mouse.Props
--- @field str_idx integer
--- @field char string
--- @field row integer
--- @field col integer
--- @field winid integer

--- @param idx integer
--- @param input_string string
--- @param chars_props Satellite.Mouse.Props[]
--- @return integer
--- @return string
--- @return Satellite.Mouse.Props[]
local function update_mouse_props(idx, input_string, chars_props)
  while true do
    idx = idx + 1
    if idx > #chars_props then
      idx = 1
      input_string, chars_props = read_input_stream()
    end
    local mouse_props = chars_props[idx]

    -- Break unless it's a mouse drag followed by another mouse drag, so
    -- that the first drag is skipped.
    if mouse_props.winid == 0 or vim.tbl_contains({ LEFTMOUSE, LEFTRELEASE }, mouse_props.char) then
      break
    end

    if idx >= #mouse_props then
      break
    end

    local next = chars_props[idx + 1]

    if next.winid == 0 or vim.tbl_contains({ LEFTMOUSE, LEFTRELEASE }, next.char) then
      break
    end
  end

  return idx, input_string, chars_props
end

--- @param char string
--- @param mouse_props Satellite.Mouse.Props
--- @return boolean
local function handle_initial_leftmouse_event(char, mouse_props)
  if mouse_props.winid < 0 then
    -- The mouse event was on the tabline or command line.
    api.nvim_feedkeys(char, 'ni', false)
    return false
  end

  local props = view.get_props(mouse_props.winid)
  if not props then
    api.nvim_feedkeys(char, 'ni', false)
    return false
  end

  -- Add 1 cell horizontal left-padding for grabbing the scrollbar. Don't
  -- add right-padding as this would extend past the window and will
  -- interfere with dragging the vertical separator to resize the window.
  if
    mouse_props.row < props.row
    or mouse_props.row >= props.row + props.height
    or mouse_props.col < props.col
    or mouse_props.col > props.col + props.width
  then
    -- The click was not on a scrollbar.
    api.nvim_feedkeys(char, 'ni', false)
    return false
  end

  -- The click was on a scrollbar.
  -- Refresh the scrollbars and check if the mouse is still over a
  -- scrollbar. If not, ignore all mouse events until a LEFTRELEASE. This
  -- approach was deemed preferable to refreshing scrollbars initially, as
  -- that could result in unintended clicking/dragging where there is no
  -- scrollbar.
  api.nvim_exec_autocmds('WinScrolled', {})
  vim.cmd.redraw()

  -- Don't restore toplines whenever a scrollbar was clicked. This
  -- prevents the window where a scrollbar is dragged from having its
  -- topline restored to the pre-drag position. This also prevents
  -- restoring windows that may have had their windows shifted during the
  -- course of scrollbar clicking/dragging, to prevent jumpiness in the
  -- display.
  props = view.get_props(mouse_props.winid)
  if not props then
    return false
  end

  if mouse_props.row < props.row or mouse_props.row >= props.row + props.height then
    while fn.getchar() ~= LEFTRELEASE do
    end
    return false
  end

  return true
end

function M.handle_leftmouse()
  -- Re-send the click, so its position can be obtained through
  -- read_input_stream().
  api.nvim_feedkeys(LEFTMOUSE, 'ni', false)
  if not view.enabled() then
    -- disabled. Process the click as it would ordinarily be
    -- processed
    return
  end

  -- Computing this prior to the first mouse event could distort the location
  -- since this could be an expensive operation (and the mouse could move).
  util.invalidate_virtual_topline_lookup()

  local count = 0
  local winid --- @type integer The target window ID for a mouse scroll.
  local scrollbar_offset --- @type integer

  --- @type integer, string, Satellite.Mouse.Props[]
  local idx, input_string, chars_props = 1, '', {}

  while true do
    idx, input_string, chars_props = update_mouse_props(idx, input_string, chars_props)
    local mouse_props = chars_props[idx]
    local str_idx = mouse_props.str_idx
    local char = mouse_props.char
    local mouse_winid = mouse_props.winid

    if char == t '<esc>' then
      api.nvim_feedkeys(input_string:sub(str_idx + #char), 'ni', false)
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
    if char ~= '\x80\xf5X' or count == 0 then
      local input_char = input_string:sub(str_idx)

      if mouse_winid == 0 then
        -- There was no mouse event.
        api.nvim_feedkeys(input_char, 'ni', false)
        return
      end

      if char == LEFTRELEASE then
        handle_leftrelease(count, input_char)
        return
      end

      if count == 0 then
        if not handle_initial_leftmouse_event(input_char, mouse_props) then
          return
        end
        local props = assert(view.get_props(mouse_winid))
        winid = mouse_winid
        scrollbar_offset = props.row - mouse_props.row
      end

      -- Only consider a scrollbar update for mouse events on windows (i.e.,
      -- not on the tabline or command line).
      if mouse_winid > 0 then
        local winheight = util.get_winheight(winid)
        local mouse_winrow = get_winrow(mouse_winid)
        local winrow = get_winrow(winid)
        local window_offset = mouse_winrow - winrow
        local row = mouse_props.row + window_offset + scrollbar_offset
        local props = view.get_props(winid)
        if not props then
          return
        end
        local row0 = math.max(0, math.min(row, winheight - props.height))
        -- Only update scrollbar if the row changed.
        if props.row ~= row0 then
          local bufnr = api.nvim_win_get_buf(winid)
          set_topline(winid, get_topline(winid, bufnr, row0, props.height))
          api.nvim_exec_autocmds('WinScrolled', {})
          vim.cmd.redraw()
        end
      end
      count = count + 1
    end
  end
end

return M
