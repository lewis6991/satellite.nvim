local function test(x, y)
  vim.cmd('echo "hello world"')
end

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
  visible_line_count_old = scrollview_visible_line_count_old,
  visible_proportion_line_old = scrollview_visible_proportion_line_old
}
