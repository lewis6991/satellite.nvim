local co = coroutine

local api = vim.api

local async_thread = {
  --- @type table<string,true>
  threads = {},
}

--- @param x thread
--- @return string
local function threadtostring(x)
  if jit then
    return string.format('%p', x)
  end
  return tostring(x):match('thread: (.*)')
end

-- Are we currently running inside an async thread
--- @return true?
function async_thread.running()
  local thread = co.running()
  local id = threadtostring(thread)
  return async_thread.threads[id]
end

-- Create an async thread
--- @param fn function
--- @return thread
function async_thread.create(fn)
  local thread = co.create(fn)
  local id = threadtostring(thread)
  async_thread.threads[id] = true
  return thread
end

-- Is the async thread finished
--- @param x thread
--- @return boolean
function async_thread.finished(x)
  if co.status(x) == 'dead' then
    local id = threadtostring(x)
    async_thread.threads[id] = nil
    return true
  end
  return false
end

---Executes a future with a callback when it is done
--- @param async_fn function: the future to execute
--- @param ... any
local function execute(async_fn, ...)
  local thread = async_thread.create(async_fn)

  local function step(...)
    local ret = { co.resume(thread, ...) }
    --- @type boolean, string|function, integer
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

    local args = { select(4, unpack(ret)) }
    args[nargs] = step
    err_or_fn(unpack(args, 1, nargs))
  end

  step(...)
end

local M = {}

---Creates an async function with a callback style function.
--- @param func function: A callback style function to be converted. The last argument must be the callback.
--- @param argc number: The number of arguments of func. Must be included.
--- @return function: Returns an async function
function M.wrap(func, argc)
  return function(...)
    return co.yield(func, argc, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
--- @generic F : function
--- @param func F
--- @return F
function M.void(func)
  return function(...)
    execute(func, ...)
  end
end

--- An async function that when called will yield to the Neovim scheduler to be
--- able to call the API.
M.scheduler = M.wrap(vim.schedule, 1)

--- Abandon an async thread
M.kill = M.wrap(function() end, 1)

local TARGET_MIN_FPS = 60
local TARGET_FRAME_TIME_NS = 10 ^ 9 / TARGET_MIN_FPS

--- Automatically yield an async thread after a certain
--- amount of time.
--- @param start_time integer
--- @param pred? fun()
--- @return integer new_start_time
function M.event_control(start_time, pred)
  local duration = vim.loop.hrtime() - start_time
  if duration > TARGET_FRAME_TIME_NS then
    M.scheduler()

    if pred and pred() == false then
      M.kill()
    end

    return vim.loop.hrtime()
  end
  return start_time
end

--- Predicate function to check whether a bufnr and winid are valid.
--- @param bufnr? integer
--- @param winid? integer
--- @return fun(): false?
function M.winbuf_pred(bufnr, winid)
  local buftick = vim.b[bufnr].changedtick

  return function()
    if bufnr then
      if not api.nvim_buf_is_valid(bufnr) then
        return false
      end
      if vim.b[bufnr].changedtick ~= buftick then
        return false
      end
    end

    if winid and not api.nvim_win_is_valid(winid) then
      return false
    end
  end
end

--- Async version of `ipairs` which internally calls async.event_control between
--- iterations.
--- @generic T
--- @param a T[]
--- @param pred fun(): false? Predicate function to check whether the context is
--- valid after scheduling.
--- @return fun(): integer, T
--- @return any
--- @return integer
function M.ipairs(a, pred)
  local start_time = vim.loop.hrtime()

  --- @param i integer
  --- @return integer?, any?
  local function iter(_, i)
    start_time = M.event_control(start_time, pred)

    i = i + 1
    local v = a[i]
    if v then
      return i, v
    end
  end

  return iter, a, 0
end

--- Async version of `pairs` which internally calls async.event_control between
--- iterations.
--- @generic K, V
--- @param t table<K, V>
--- @param pred fun(): false? Predicate function to check whether the context is
--- valid after scheduling.
--- @return fun(): K, V
--- @return any
--- @return K?
function M.pairs(t, pred)
  local start_time = vim.loop.hrtime()

  local function iter(_, k)
    start_time = M.event_control(start_time, pred)
    return next(t, k)
  end

  return iter, t, nil
end

return M
