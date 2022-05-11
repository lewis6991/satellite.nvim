
local M = {}

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

function M.debouncer(ms)
  -- nil   : No timers active, function needs to be debounced
  -- true  : Timer active
  -- false : Timer finished, next function call can run.
  ---@type table<any,boolean>
  local state = {}

  return function(id)
    if state[id] == true then
      -- Timer is active
      return true
    end

    if state[id] == nil then
      state[id] = true
      local timer = vim.loop.new_timer()
      timer:start(ms, 0, function()
        state[id] = false
        timer:stop()
      end)
      -- Timer is active
      return true
    end

    state[id] = nil
  end
end

return M
