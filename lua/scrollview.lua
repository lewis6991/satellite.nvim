local api = vim.api

-- *************************************************
-- * Memoization
-- *************************************************

local cache = {}
local memoize = false

local function start_memoize()
  memoize = true
end

local function stop_memoize()
  memoize = false
end

local function reset_memoize()
  cache = {}
end

-- *************************************************
-- * Utils
-- *************************************************

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local function round(x)
  return math.floor(x + 0.5)
end

-- *************************************************
-- * Core
-- *************************************************

-- Creates a temporary floating window that can be used for computations
-- ---corresponding to the specified window---that require temporary cursor
-- movements (e.g., counting virtual lines, where all lines in a closed fold
-- are counted as a single line). This can be used instead of working in the
-- actual window, to prevent unintended side-effects that arise from moving the
-- cursor in the actual window, even when autocmd's are disabled with
-- eventignore=all and the cursor is restored (e.g., Issue #18: window
-- flickering when resizing with the mouse, Issue #19: cursorbind/scrollbind
-- out-of-sync). It's the caller's responsibility to close the workspace
-- window.
local function open_win_workspace(winid)
  -- Make the target window active, so that its folds are inherited by the
  -- created floating window (this is necessary when there are multiple windows
  -- that have the same buffer, each window having different folds).
  local workspace_winid = api.nvim_win_call(winid, function()
    local bufnr = api.nvim_win_get_buf(winid)
    return api.nvim_open_win(bufnr, false, {
      relative = 'editor',
      focusable = false,
      width = math.max(1, api.nvim_win_get_width(winid)),
      height = math.max(1, api.nvim_win_get_height(winid)),
      row = 0,
      col = 0
    })
  end)
  -- Disable scrollbind and cursorbind on the workspace window so that diff
  -- mode and other functionality that utilizes binding (e.g., :Gdiff, :Gblame)
  -- can function properly.
  api.nvim_win_set_option(workspace_winid, 'scrollbind', false)
  api.nvim_win_set_option(workspace_winid, 'cursorbind', false)
  return workspace_winid
end

-- Advance the current window cursor to the start of the next virtual span,
-- returning the range of lines jumped over, and a boolean indicating whether
-- that range was in a closed fold. A virtual span is a contiguous range of
-- lines that are either 1) not in a closed fold or 2) in a closed fold. If
-- there is no next virtual span, the cursor is returned to the first line.
local function advance_virtual_span()
  local start = vim.fn.line('.')
  local foldclosedend = vim.fn.foldclosedend(start)
  if foldclosedend ~= -1 then
    -- The cursor started on a closed fold.
    if foldclosedend == vim.fn.line('$') then
      vim.cmd('keepjumps normal! gg')
    else
      vim.cmd('keepjumps normal! j')
    end
    return start, foldclosedend, true
  end
  local lnum = start
  while true do
    vim.cmd('keepjumps normal! zj')
    if lnum == vim.fn.line('.') then
      -- There are no more folds after the cursor. This is the last span.
      vim.cmd('keepjumps normal! gg')
      return start, vim.fn.line('$'), false
    end
    lnum = vim.fn.line('.')
    local foldclosed = vim.fn.foldclosed(lnum)
    if foldclosed ~= -1 then
      -- The cursor moved to a closed fold. The preceding line ends the prior
      -- virtual span.
      return start, lnum - 1, false
    end
  end
end

-- Returns a boolean indicating whether the count of folds (closed folds count
-- as a single fold) between the specified start and end lines exceeds 'n', in
-- the current window. The cursor may be moved.
local function fold_count_exceeds(start, _end, n)
  vim.cmd('keepjumps normal! ' .. start .. 'G')
  if vim.fn.foldclosed(start) ~= -1 then
    n = n - 1
  end
  if n < 0 then
    return true
  end
  -- Navigate down n folds.
  if n > 0 then
    vim.cmd('keepjumps normal! ' .. n .. 'zj')
  end
  local line1 = vim.fn.line('.')
  -- The fold count exceeds n if there is another fold to navigate to on a line
  -- less than _end.
  vim.cmd('keepjumps normal! zj')
  local line2 = vim.fn.line('.')
  return line2 > line1 and line2 <= _end
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the current window. A closed fold counts as one virtual
-- line. The computation loops over virtual spans. The cursor may be moved.
local function virtual_line_count_spanwise(start, _end)
  start = math.max(1, start)
  _end = math.min(vim.fn.line('$'), _end)
  local count = 0
  if _end >= start then
    vim.cmd('keepjumps normal! ' .. start .. 'G')
    while true do
      local range_start, range_end, fold = advance_virtual_span()
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
  return count
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the current window. A closed fold counts as one virtual
-- line. The computation loops over lines.
local function virtual_line_count_linewise(start, _end)
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

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as one
-- virtual line. The computation loops over lines. The cursor is not moved.
local function virtual_line_count(winid, start, _end)
  local last_line = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
  if type(_end) == 'string' and _end == '$' then
    _end = last_line
  end
  local memoize_key =
    table.concat({'virtual_line_count', winid, start, _end}, ':')
  if memoize and cache[memoize_key] then return cache[memoize_key] end
  local workspace_winid = open_win_workspace(winid)
  local count = api.nvim_win_call(workspace_winid, function()
    -- On an AMD Ryzen 7 2700X, linewise computation takes about 3e-7 seconds
    -- per line (this is an overestimate, as it assumes all folds are open, but
    -- the time is reduced when there are closed folds, as lines would be
    -- skipped). Spanwise computation takes about 5e-5 seconds per fold (closed
    -- folds count as a single fold). Therefore the linewise computation is
    -- worthwhile when the number of folds is greater than (3e-7 / 5e-5) * L =
    -- .006L, where L is the number of lines.
    if fold_count_exceeds(start, _end, math.floor(last_line * .006)) then
      return virtual_line_count_linewise(start, _end)
    else
      return virtual_line_count_spanwise(start, _end)
    end
  end)
  api.nvim_win_close(workspace_winid, true)
  if memoize then cache[memoize_key] = count end
  return count
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation loops over virtual spans. The cursor may be moved.
local function virtual_topline_lookup_spanwise()
  local winheight = api.nvim_win_get_height(0)
  local result = {}  -- A list of line numbers
  local winid = api.nvim_get_current_win()
  local virtual_line_count = virtual_line_count(winid, 1, '$')
  if virtual_line_count > 1 and winheight > 1 then
    local line = 0
    local virtual_line = 0
    local prop = 0.0
    local row = 1
    local proportion = (row - 1) / (winheight - 1)
    vim.cmd('keepjumps normal! gg')
    while #result < winheight do
      local range_start, range_end, fold = advance_virtual_span()
      local line_delta = range_end - range_start + 1
      local virtual_line_delta = 1
      if not fold then
        virtual_line_delta = line_delta
      end
      local prop_delta = virtual_line_delta / (virtual_line_count - 1)
      while prop + prop_delta >= proportion and #result < winheight do
        local ratio = (proportion - prop) / prop_delta
        local topline = line + 1
        if fold then
          -- If ratio >= 0.5, add all lines in the fold, otherwise don't add
          -- the fold.
          if ratio >= 0.5 then
            topline = topline + line_delta
          end
        else
          topline = topline + round(ratio * line_delta)
        end
        table.insert(result, topline)
        row = row + 1
        proportion = (row - 1) / (winheight - 1)
      end
      -- A line number of 1 indicates that advance_virtual_span looped back to
      -- the beginning of the document.
      local looped = vim.fn.line('.') == 1
      if looped or #result >= winheight then
        break
      end
      line = line + line_delta
      virtual_line = virtual_line + virtual_line_delta
      prop = virtual_line / (virtual_line_count - 1)
    end
  end
  while #result < winheight do
    table.insert(result, vim.fn.line('$'))
  end
  for idx, line in ipairs(result) do
    line = math.max(1, line)
    line = math.min(vim.fn.line('$'), line)
    local foldclosed = vim.fn.foldclosed(line)
    if foldclosed ~= -1 then
      line = foldclosed
    end
    result[idx] = line
  end
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode, in the current window.
-- The computation loops over lines.
local function virtual_topline_lookup_linewise()
  local winheight = api.nvim_win_get_height(0)
  local last_line = vim.fn.line('$')
  local result = {}  -- A list of line numbers
  local winid = api.nvim_get_current_win()
  local virtual_line_count = virtual_line_count(winid, 1, '$')
  if virtual_line_count > 1 and winheight > 1 then
    local count = 1  -- The count of virtual lines
    local line = 1
    local best = line
    local best_distance = math.huge
    local best_count = count
    for row=1,winheight do
      local proportion = (row - 1) / (winheight - 1)
      while line <= last_line do
        local current = (count - 1) / (virtual_line_count - 1)
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
        foldclosedend = vim.fn.foldclosedend(line)
        if foldclosedend ~= -1 then
          line = foldclosedend
        end
        line = line + 1
        count = count + 1
      end
      local value = best
      local foldclosed = vim.fn.foldclosed(value)
      if foldclosed ~= -1 then
        value = foldclosed
      end
      table.insert(result, value)
    end
  end
  return result
end

-- Returns an array that maps window rows to the topline that corresponds to a
-- scrollbar at that row under virtual scrollview mode. The cursor is not
-- moved.
local function virtual_topline_lookup(winid)
  local workspace_winid = open_win_workspace(winid)
  local result = api.nvim_win_call(workspace_winid, function()
    local last_line = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
    -- On an AMD Ryzen 7 2700X, linewise computation takes about 1.6e-6 seconds
    -- per line (this is an overestimate, as it assumes all folds are open, but
    -- the time is reduced when there are closed folds, as lines would be
    -- skipped). Spanwise computation takes about 6.5e-5 seconds per fold
    -- (closed folds count as a single fold). Therefore the linewise
    -- computation is worthwhile when the number of folds is greater than
    -- (1.6e-6 / 6.5e-5) * L = .0246L, where L is the number of lines.
    if fold_count_exceeds(1, last_line, math.floor(last_line * .0246)) then
      return virtual_topline_lookup_linewise()
    else
      return virtual_topline_lookup_spanwise()
    end
  end)
  api.nvim_win_close(workspace_winid, true)
  return result
end

return {
  open_win_workspace = open_win_workspace,
  reset_memoize = reset_memoize,
  start_memoize = start_memoize,
  stop_memoize = stop_memoize,
  virtual_line_count = virtual_line_count,
  virtual_topline_lookup = virtual_topline_lookup
}
