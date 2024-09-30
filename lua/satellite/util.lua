local api = vim.api
local fn = vim.fn

local M = {}

--- @generic F: function
--- @param f F
--- @param ms integer
--- @return F
function M.debounce_trailing(f, ms)
  local timer = assert(vim.loop.new_timer())
  return function(...)
    local argv = { ... }
    timer:start(ms or 100, 0, function()
      vim.schedule(function()
        timer:stop()
        f(unpack(argv))
      end)
    end)
  end
end

--- @type table<integer,table<integer,table<integer,integer>>>
local virtual_line_count_cache = vim.defaulttable()

function M.invalidate_virtual_line_count_cache(winid)
  virtual_line_count_cache[winid] = nil
end

--- Returns the count of virtual lines between the specified start and end lines
--- (both inclusive), in the specified window. A closed fold counts as one
--- virtual line.
--- @param winid integer
--- @param start integer
--- @param vend? integer
--- @return integer
function M.virtual_line_count(winid, start, vend)
  if not vend then
    local buf = api.nvim_win_get_buf(winid)
    vend = api.nvim_buf_line_count(buf) - 1
  end

  if vend == 0 then
    return 0
  end

  local cached = rawget(virtual_line_count_cache[winid][start], vend)
  if cached then
    return cached
  end

  if api.nvim_win_text_height then
    local ok, res = pcall(api.nvim_win_text_height, winid, {
      start_row = start,
      end_row = vend,
    })
    if ok then
      if type(res) == 'table' then
        res = res.all
      end
      virtual_line_count_cache[winid][start][vend] = res
      return res
    end
  end

  return api.nvim_win_call(winid, function()
    local vline = 0
    local line = start
    while line <= vend do
      vline = vline + 1
      local foldclosedend = fn.foldclosedend(line)
      if foldclosedend ~= -1 then
        line = foldclosedend
      end
      -- This function is called a lot so cache every line
      virtual_line_count_cache[winid][start][line] = vline
      line = line + 1
    end
    return vline
  end)
end

--- @type table<integer,integer[]>
local virtual_topline_lookup_cache = vim.defaulttable()

function M.invalidate_virtual_topline_lookup()
  virtual_topline_lookup_cache = vim.defaulttable()
end

--- Returns the height of a window excluding the winbar
--- @param winid integer
--- @return integer
function M.get_winheight(winid)
  local winheight = api.nvim_win_get_height(winid)

  if vim.wo[winid].winbar ~= '' then
    winheight = winheight - 1
  end

  return winheight
end

--- Returns an array that maps window rows to the topline that corresponds to a
--- scrollbar at that row under virtual satellite mode, in the current window.
--- The computation primarily loops over lines, but may loop over virtual spans
--- as part of calling 'virtual_line_count', so the cursor may be moved.
--- @param winid integer
--- @return table<integer,integer>
function M.virtual_topline_lookup(winid)
  if rawget(virtual_topline_lookup_cache, winid) then
    return virtual_topline_lookup_cache[winid]
  end

  local winheight = M.get_winheight(winid)
  local total_vlines = M.virtual_line_count(winid, 1)
  if not (total_vlines > 1 and winheight > 1) then
    virtual_topline_lookup_cache[winid] = {}
    return virtual_topline_lookup_cache[winid]
  end

  local bufnr = api.nvim_win_get_buf(winid)
  local last_line = api.nvim_buf_line_count(bufnr)

  virtual_topline_lookup_cache[winid] = api.nvim_win_call(winid, function()
    local result = {} --- @type integer[] A list of line numbers
    local count = 1 -- The count of virtual lines
    local line = 1
    local best = line
    local best_distance = math.huge
    local best_count = count
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
    return result
  end)

  return virtual_topline_lookup_cache[winid]
end

--- Round to the nearest integer.
--- WARN: .5 rounds to the right on the number line, including for negatives
--- (which would not result in rounding up in magnitude).
--- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
--- @param x number
--- @return integer
function M.round(x)
  return math.floor(x + 0.5)
end

--- @param winid integer
--- @param row integer
--- @param row2 integer
--- @return number
local function height_to_virtual(winid, row, row2)
  local vlinecount0 = M.virtual_line_count(winid, 1) - 1
  local vheight = M.virtual_line_count(winid, row, row2)
  local winheight0 = M.get_winheight(winid) - 1
  return winheight0 * vheight / vlinecount0
end

--- @param winid integer
--- @param row integer
--- @param row2 integer
--- @return integer
function M.height_to_virtual(winid, row, row2)
  local height = M.round(height_to_virtual(winid, row, row2))
  if height < 1 then
    height = 1
  end
  return height
end

--- @param winid integer
--- @param row integer
--- @return integer, number
function M.row_to_barpos(winid, row)
  local v = height_to_virtual(winid, 1, row)
  local vr = M.round(v)
  return vr, vr - v
end

--- Run callback when command is run
--- @param cmd string
--- @param augroup string|integer
--- @param f function()
function M.on_cmd(cmd, augroup, f)
  api.nvim_create_autocmd('CmdlineLeave', {
    group = augroup,
    callback = function()
      if fn.getcmdtype() == ':' and vim.startswith(fn.getcmdline(), cmd) then
        f()
      end
    end,
  })
end

--- Returns true for ordinary windows (not floating and not external), and false
--- otherwise.
--- @param winid integer
--- @return boolean
function M.is_ordinary_window(winid)
  local cfg = api.nvim_win_get_config(winid)
  local not_external = not cfg['external']
  local not_floating = cfg['relative'] == ''
  return not_external and not_floating
end

--- Return top line and bottom line in window. For folds, the top line
--- represents the start of the fold and the bottom line represents the end of
--- the fold.
--- @param winid integer
--- @return integer, integer
function M.visible_line_range(winid)
  -- WARN: getwininfo(winid)[1].botline is not properly updated for some
  -- movements (Neovim Issue #13510), so this is implemeneted as a workaround.
  return unpack(api.nvim_win_call(winid, function()
    local topline = fn.line('w0')
    -- line('w$') returns 0 in silent Ex mode, but line('w0') is always greater
    -- than or equal to 1.
    local botline = math.max(fn.line('w$'), topline)
    --- @diagnostic disable-next-line:redundant-return-value
    return { topline, botline }
  end))
end

--- @generic F: function
--- @param f F
--- @return F
function M.noautocmd(f)
  return function(...)
    local eventignore = vim.o.eventignore
    vim.o.eventignore = 'all'
    local r = { pcall(f, ...) }
    vim.o.eventignore = eventignore
    if not r[1] then
      error(r[2])
    end
    return unpack(r, 2, table.maxn(r))
  end
end

function M.in_cmdline_win(winid)
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

return M
