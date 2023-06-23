local fn, api = vim.fn, vim.api

local util = require 'satellite.util'
local view = require 'satellite.view'

-- Replace termcodes.
--- @param str string
--- @return string
local function t(str)
  return api.nvim_replace_termcodes(str, true, true, true)
end

local MOUSEDOWN = t('<leftmouse>')
local MOUSEUP = t('<leftrelease>')

local function is_visual_mode()
  local mode = fn.mode()
  return vim.tbl_contains({ 'v', 'V', t '<c-v>' }, mode)
end

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

-- Scrolls the window so that the specified line number is at the top.
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

local function getchar()
  local ok, char = pcall(fn.getchar)
  if not ok then
    -- E.g., <c-c>
    char = t '<esc>'
  end
  -- For Vim on Cygwin, pressing <c-c> during getchar() does not raise
  -- "Vim:Interrupt". Handling for such a scenario is added here as a
  -- precaution, by converting to <esc>.
  if char == t '<c-c>' then
    char = t '<esc>'
  end
  if type(char) == 'number' then
    char = tostring(char)
  end
  return char
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
  local str_idx = 1 -- in bytes, 1-indexed
  while true do
    local char = getchar()
    local charmod = fn.getcharmod()
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

    local char_props = {
      char = char,
      str_idx = str_idx,
      charmod = charmod,
      mouse_winid = mouse_winid,
      mouse_row = mouse_row,
      mouse_col = mouse_col,
    }

    str_idx = str_idx + string.len(char)
    table.insert(chars_props, char_props)
    -- Break if there are no more items on the input stream.
    if fn.getchar(1) == 0 then
      break
    end
  end
  local string = table.concat(chars, '')
  return string, chars_props
end

local M = {}

function M.handle_leftmouse()
  -- Re-send the click, so its position can be obtained through
  -- read_input_stream().
  fn.feedkeys(MOUSEDOWN, 'ni')
  if not view.enabled() then
    -- disabled. Process the click as it would ordinarily be
    -- processed
    return
  end
  local count = 0
  local winid -- The target window ID for a mouse scroll.
  local bufnr -- The target buffer number.
  local scrollbar_offset
  local idx = 1
  local input_string, chars_props = '', {}
  local str_idx, char, mouse_winid, mouse_row, mouse_col
  -- Computing this prior to the first mouse event could distort the location
  -- since this could be an expensive operation (and the mouse could move).
  util.invalidate_virtual_topline_lookup()
  while true do
    while true do
      idx = idx + 1
      if idx > #chars_props then
        idx = 1
        input_string, chars_props = read_input_stream()
      end
      local char_props = chars_props[idx]
      str_idx = char_props.str_idx
      char = char_props.char
      mouse_winid = char_props.mouse_winid
      mouse_row = char_props.mouse_row
      mouse_col = char_props.mouse_col
      -- Break unless it's a mouse drag followed by another mouse drag, so
      -- that the first drag is skipped.
      if mouse_winid == 0 or vim.tbl_contains({ MOUSEDOWN, MOUSEUP }, char) then
        break
      end
      if idx >= #char_props then
        break
      end
      local next = chars_props[idx + 1]
      if next.mouse_winid == 0 or vim.tbl_contains({ MOUSEDOWN, MOUSEUP }, next.char) then
        break
      end
    end

    if char == t '<esc>' then
      fn.feedkeys(string.sub(input_string, str_idx + #char), 'ni')
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
        fn.feedkeys(string.sub(input_string, str_idx), 'ni')
        return
      end

      if char == MOUSEUP then
        if count == 0 then
          -- No initial MOUSEDOWN was captured.
          fn.feedkeys(string.sub(input_string, str_idx), 'ni')
        elseif count == 1 then
          -- A scrollbar was clicked, but there was no corresponding drag.
          -- Allow the interaction to be processed as it would be with no
          -- scrollbar.
          fn.feedkeys(MOUSEDOWN .. string.sub(input_string, str_idx), 'ni')
        else
          -- A scrollbar was clicked and there was a corresponding drag.
          -- 'feedkeys' is not called, since the full mouse interaction has
          -- already been processed. The current window (from prior to
          -- scrolling) is not changed.
          view.refresh_bars()
        end
        return
      end

      if count == 0 then
        if mouse_winid < 0 then
          -- The mouse event was on the tabline or command line.
          fn.feedkeys(string.sub(input_string, str_idx), 'ni')
          return
        end

        local props = view.get_props(mouse_winid)
        if not props then
          fn.feedkeys(string.sub(input_string, str_idx), 'ni')
          return
        end

        -- Add 1 cell horizontal left-padding for grabbing the scrollbar. Don't
        -- add right-padding as this would extend past the window and will
        -- interfere with dragging the vertical separator to resize the window.
        if
          mouse_row < props.row
          or mouse_row >= props.row + props.height
          or mouse_col < props.col
          or mouse_col > props.col + props.width
        then
          -- The click was not on a scrollbar.
          fn.feedkeys(string.sub(input_string, str_idx), 'ni')
          return
        end

        -- The click was on a scrollbar.
        -- Refresh the scrollbars and check if the mouse is still over a
        -- scrollbar. If not, ignore all mouse events until a MOUSEUP. This
        -- approach was deemed preferable to refreshing scrollbars initially, as
        -- that could result in unintended clicking/dragging where there is no
        -- scrollbar.
        view.refresh_bars()

        -- Don't restore toplines whenever a scrollbar was clicked. This
        -- prevents the window where a scrollbar is dragged from having its
        -- topline restored to the pre-drag position. This also prevents
        -- restoring windows that may have had their windows shifted during the
        -- course of scrollbar clicking/dragging, to prevent jumpiness in the
        -- display.
        props = view.get_props(mouse_winid)
        if not props then
          return
        end

        if mouse_row < props.row or mouse_row >= props.row + props.height then
          while fn.getchar() ~= MOUSEUP do
          end
          return
        end

        -- By this point, the click on a scrollbar was successful.
        if is_visual_mode() then
          -- Exit visual mode.
          vim.cmd('normal! ' .. t '<esc>')
        end
        winid = mouse_winid
        bufnr = api.nvim_win_get_buf(winid)
        scrollbar_offset = props.row - mouse_row
      end

      -- Only consider a scrollbar update for mouse events on windows (i.e.,
      -- not on the tabline or command line).
      if mouse_winid > 0 then
        local winheight = util.get_winheight(winid)
        local mouse_winrow = fn.getwininfo(mouse_winid)[1].winrow
        local winrow = fn.getwininfo(winid)[1].winrow
        local window_offset = mouse_winrow - winrow
        local row = mouse_row + window_offset + scrollbar_offset
        local props = view.get_props(winid)
        if not props then
          return
        end
        -- row is 1-based (see getmousepos()), so need to pass in 0-based
        local row0 = math.max(0, math.min(row - 1, winheight - props.height))
        -- Only update scrollbar if the row changed.
        if props.row ~= row0 then
          set_topline(winid, get_topline(winid, bufnr, row0, props.height))
          if vim.wo[winid].scrollbind or vim.wo[winid].cursorbind then
            M.refresh_bars()
          end
          view.move_scrollbar(winid, row0)
        end
      end
      count = count + 1
    end
  end
end

return M
