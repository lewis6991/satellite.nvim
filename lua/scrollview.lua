-- Returns the count of visible lines between the specified start and end
-- lines, in the current window's buffer.
local function scrollview_visible_line_count(start, _end)
  local count = 0
  if start < 1 then
    start = 1
  end
  if _end > vim.fn.line('$') then
    _end = vim.fn.line('$')
  end
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

return {
  visible_line_count = scrollview_visible_line_count
}
