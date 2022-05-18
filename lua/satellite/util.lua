local api = vim.api
local fn = vim.fn

local M = {}

-- NOTE:
-- Set window option.
-- Workaround for nvim bug where nvim_win_set_option "leaks" local
-- options to windows created afterwards (thanks @sindrets!)
-- SEE:
-- https://github.com/b0o/incline.nvim/issues/4
-- https://github.com/neovim/neovim/issues/18283
-- https://github.com/neovim/neovim/issues/14670
-- https://github.com/neovim/neovim#9110
function M.set_window_option(winid, key, value)
    -- Convert to Vim format (e.g., 1 instead of Lua true).
    if value == true then
      value = 1
    elseif value == false then
      value = 0
    end
    -- setwinvar(..., '&...', ...) is used in place of nvim_win_set_option
    -- to avoid Neovim Issues #15529 and #15531, where the global window option
    -- is set in addition to the window-local option, when using Neovim's API or
    -- Lua interface.
    vim.fn.setwinvar(winid, '&' .. key, value)
end


function M.debounce_trailing(f, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local argv = {...}
    timer:start(ms or 100, 0, function()
      vim.schedule(function()
        timer:stop()
        f(unpack(argv))
      end)
    end)
  end
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

function M.invalidate_virtual_line_count_cache(winid)
  virtual_line_count_cache[winid] = nil
end

-- Returns the count of virtual lines between the specified start and end lines
-- (both inclusive), in the specified window. A closed fold counts as one
-- virtual line. The computation loops over either lines or virtual spans, so
-- the cursor may be moved.
function M.virtual_line_count(winid, start, vend)
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

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
local function round(x)
  return math.floor(x + 0.5)
end

function M.row_to_barpos(winid, row)
  local vlinecount0 = M.virtual_line_count(winid, 1) - 1
  local vrow = M.virtual_line_count(winid, 1, row)
  local winheight0 = api.nvim_win_get_height(winid) - 1
  return round(winheight0 * vrow / vlinecount0)
end

--- Run callback when command is run
---@param cmd string
---@param augroup string|integer
---@param f function()
function M.on_cmd(cmd, augroup, f)
  api.nvim_create_autocmd({'CmdlineLeave'}, {
    group = augroup,
    callback = function()
      if fn.getcmdtype() == ':' and vim.startswith(fn.getcmdline(), cmd) then
        f()
      end
    end
  })
end

return M
