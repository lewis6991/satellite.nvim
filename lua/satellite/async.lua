local co = coroutine

local async_thread = {
  threads = {},
}

local function threadtostring(x)
  if jit then
    return string.format('%p', x)
  else
    return tostring(x):match('thread: (.*)')
  end
end

-- Are we currently running inside an async thread
function async_thread.running()
  local thread = co.running()
  local id = threadtostring(thread)
  return async_thread.threads[id]
end

-- Create an async thread
function async_thread.create(fn)
  local thread = co.create(fn)
  local id = threadtostring(thread)
  async_thread.threads[id] = true
  return thread
end

-- Is the async thread finished
function async_thread.finished(x)
  if co.status(x) == 'dead' then
    local id = threadtostring(x)
    async_thread.threads[id] = nil
    return true
  end
  return false
end

---Executes a future with a callback when it is done
---@param async_fn function: the future to execute
local function execute(async_fn, ...)
  local thread = async_thread.create(async_fn)

  local function step(...)
    local ret = { co.resume(thread, ...) }
    local stat, err_or_fn, nargs = unpack(ret)

    if not stat then
      error(
        string.format(
          'The coroutine failed with this message: %s\n%s',
          err_or_fn,
          debug.traceback(thread)
        )
      )
    end

    if async_thread.finished(thread) then
      return
    end

    assert(type(err_or_fn) == 'function', 'type error :: expected func')

    local ret_fn = err_or_fn
    local args = { select(4, unpack(ret)) }
    args[nargs] = step
    ret_fn(unpack(args, 1, nargs))
  end

  step(...)
end

local M = {}

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func, argc)
  return function(...)
    if not async_thread.running() then
      -- print(debug.traceback('Warning: calling async function in non-async context', 2))
      return func(...)
    end
    return co.yield(func, argc, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@generic F : function
---@param func F
---@return F
function M.void(func)
  return function(...)
    if async_thread.running() then
      -- print(debug.traceback('Warning: calling void function in async context', 2))
      return func(...)
    end
    execute(func, ...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1)

local TARGET_MIN_FPS = 10
local TARGET_FRAME_TIME_NS = 10^9 / TARGET_MIN_FPS

function M.event_control(start_time)
  local duration = vim.loop.hrtime() - start_time
  if duration > TARGET_FRAME_TIME_NS then
    M.scheduler()
    return vim.loop.hrtime()
  end
  return start_time
end

return M
