-- Advance the current window cursor to the start of the next visible span,
-- returning the range of lines jumped over, and a boolean indicating whether
-- that range was in a closed fold. If there is no next visible span, the
-- cursor is returned to the first line.
local function scrollview_advance_visible_span()
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

local function scrollview_virtual_line_count(winid, start, _end)
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
      local range_start, range_end, fold =
        unpack(scrollview_advance_visible_span())
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

-- TODO: DELETE
-- Returns the count of visible lines between the specified start and end
-- lines, in the current window's buffer.
local function scrollview_visible_line_count(start, _end)
  if start < 1 then
    start = 1
  end
  if _end > vim.fn.line('$') then
    _end = vim.fn.line('$')
  end
  local count = 0
  local line = start
  while line <= _end do
    count = count + 1
    foldclosedend = vim.fn.foldclosedend(line)
    if foldclosedend ~= -1 then
      line = foldclosedend
    end
    line = line + 1
  end
  return count
end

-- TODO: DELETE
-- Returns the count of visible lines between the specified start and end
-- lines, in the current window's buffer.
local function scrollview_visible_line_count_old(start, _end)
  if start < 1 then
    start = 1
  end
  if _end > vim.fn.line('$') then
    _end = vim.fn.line('$')
  end
  local count = 0
  local line = start
  while line <= _end do
    count = count + 1
    foldclosedend = vim.fn.foldclosedend(line)
    if foldclosedend ~= -1 then
      line = foldclosedend
    end
    line = line + 1
  end
  return count
end

-- TODO: DELETE
-- Returns the line at the approximate visible proportion between the specified
-- start and end lines, in the current window's buffer. If the result is in a
-- closed fold, it is converted to the first line in that fold.
local function scrollview_visible_proportion_line_old(start, _end, proportion)
  if start < 1 then
    start = 1
  end
  if _end > vim.fn.line('$') then
    _end = vim.fn.line('$')
  end
  local total = scrollview_visible_line_count_old(start, _end)
  local best = start
  local best_distance = math.huge
  if total > 1 then
    local count = 0
    local line = start
    while line <= _end do
      count = count + 1
      local current = (count - 1) / (total - 1)
      local distance = math.abs(current - proportion)
      if distance < best_distance then
        best = line
        best_distance = distance
      end
      foldclosedend = vim.fn.foldclosedend(line)
      if foldclosedend ~= -1 then
        line = foldclosedend
      end
      line = line + 1
    end
  end
  local foldclosed = vim.fn.foldclosed(best)
  if foldclosed ~= -1 then
    best = foldclosed
  end
  return best
end

return {
  advance_visible_span = scrollview_advance_visible_span, -- TODO: REMOVE
  virtual_line_count = scrollview_virtual_line_count,
  visible_proportion_line_old = scrollview_visible_proportion_line_old -- TODO: REMOVE
}
