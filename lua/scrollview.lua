-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local function round(x)
  return math.floor(x + 0.5)
end

-- Advance the current window cursor to the start of the next visible span,
-- returning the range of lines jumped over, and a boolean indicating whether
-- that range was in a closed fold. If there is no next visible span, the
-- cursor is returned to the first line.
local function advance_visible_span()
  local start = vim.fn.line('.')
  local foldclosedend = vim.fn.foldclosedend(start)
  if foldclosedend ~= -1 then
    -- The cursor started on a closed fold.
    if foldclosedend == vim.fn.line('$') then
      vim.cmd('keepjumps normal! gg')
    else
      vim.cmd('keepjumps normal! j')
    end
    return {start, foldclosedend, true}
  end
  local lnum = start
  while true do
    vim.cmd('keepjumps normal! zj')
    if lnum == vim.fn.line('.') then
      -- There are no more folds after the cursor. This is the last span.
      vim.cmd('keepjumps normal! gg')
      return {start, vim.fn.line('$'), false}
    end
    lnum = vim.fn.line('.')
    local foldclosed = vim.fn.foldclosed(lnum)
    if foldclosed ~= -1 then
      -- The cursor moved to a closed fold. The preceding line ends the prior
      -- visible span.
      return {start, lnum - 1, false}
    end
  end
end

-- Returns the count of visible lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as on
-- visible line. '$' can be used as the end line, to represent the last line.
local function virtual_line_count(winid, start, _end)
  local current_winid = vim.fn.win_getid(vim.fn.winnr())
  vim.fn.win_gotoid(winid)
  -- Temporarily disable scrollbind and cursorbind so that diff mode and other
  -- functinoality that utilizes binding (e.g., :Gdiff, :Gblame) can function
  -- properly.
  local scrollbind = vim.wo.scrollbind
  local cursorbind = vim.wo.cursorbind
  vim.wo.scrollbind = false
  vim.wo.cursorbind = false
  local view = vim.fn.winsaveview()
  if type(_end) == 'string' and _end == '$' then
    _end = vim.fn.line('$')
  end
  start = math.max(1, start)
  _end = math.min(vim.fn.line('$'), _end)
  local count = 0
  if _end >= start then
    vim.cmd('keepjumps normal! ' .. start .. 'G')
    while true do
      local range_start, range_end, fold = unpack(advance_visible_span())
      range_end = math.min(range_end, _end)
      local delta = 1
      if not fold then
        delta = range_end - range_start + 1
      end
      count = count + delta
      if range_end == _end or vim.fn.line('.') == 1 then
        break
      end
    end
  end
  vim.fn.winrestview(view)
  vim.wo.scrollbind = scrollbind
  vim.wo.cursorbind = cursorbind
  vim.fn.win_gotoid(current_winid)
  return count
end

-- Return the line at the approximate virtual proportion in the specified
-- window. If the result is in a closed fold, it is converted to the first line
-- in that fold.
local function virtual_proportion_line(winid, proportion)
  local current_winid = vim.fn.win_getid(vim.fn.winnr())
  vim.fn.win_gotoid(winid)
  -- Temporarily disable scrollbind and cursorbind so that diff mode and other
  -- functinoality that utilizes binding (e.g., :Gdiff, :Gblame) can function
  -- properly.
  local scrollbind = vim.wo.scrollbind
  local cursorbind = vim.wo.cursorbind
  vim.wo.scrollbind = false
  vim.wo.cursorbind = false
  local view = vim.fn.winsaveview()
  local line = 0
  local virtual_line = 0
  local prop = 0.0
  local virtual_line_count = virtual_line_count(winid, 1, '$')
  if virtual_line_count > 1 then
    vim.cmd('keepjumps normal! gg')
    while true do
      local range_start, range_end, fold = unpack(advance_visible_span())
      local line_delta = range_end - range_start + 1
      local virtual_line_delta = 1
      if not fold then
        virtual_line_delta = line_delta
      end
      local prop_delta = virtual_line_delta / (virtual_line_count - 1)
      if prop + prop_delta >= proportion then
        local ratio = (proportion - prop) / prop_delta
        prop = prop + (ratio * prop_delta)
        line = line + round(ratio * line_delta) + 1
        break
      end
      line = line + line_delta
      virtual_line = virtual_line + virtual_line_delta
      prop = virtual_line / (virtual_line_count - 1)
      if vim.fn.line('.') == 1 then
        -- advance_visible_span looped back to the beginning of the document.
        line = vim.fn.line('$')
        break
      end
    end
  end
  line = math.max(1, line)
  line = math.min(vim.fn.line('$'), line)
  local foldclosed = vim.fn.foldclosed(line)
  if foldclosed ~= -1 then
    line = foldclosed
  end
  vim.fn.winrestview(view)
  vim.wo.scrollbind = scrollbind
  vim.wo.cursorbind = cursorbind
  vim.fn.win_gotoid(current_winid)
  return line
end

return {
  virtual_line_count = virtual_line_count,
  virtual_proportion_line = virtual_proportion_line
}
