local M = {}

local yield_marker = {}

local function resume(thread, ...)
  --- @type [boolean, {}, string|fun(callback: fun(...))]]
  local ret = { coroutine.resume(thread, ...) }
  local stat = ret[1]

  if not stat then
    error(debug.traceback(thread, ret[2]), 0)
  elseif coroutine.status(thread) == 'dead' then
    return
  end

  local marker, fn = ret[2], ret[3]

  assert(type(fn) == 'function', 'type error :: expected func')

  if marker ~= yield_marker or not vim.is_callable(fn) then
    return error('Unexpected coroutine.yield')
  end

  local ok, perr = pcall(fn, function(...)
    resume(thread, ...)
  end)
  if not ok then
    resume(thread, perr)
  end
end

---Executes a future with a callback when it is done
--- @param async_fn async fun() the future to execute
--- @param ... any
function M.run(async_fn, ...)
  resume(coroutine.create(async_fn), ...)
end

local function check(err, ...)
  if err then
    error(err, 0)
  end
  return ...
end

--- @async
function M.await(argc, func, ...)
  if type(argc) == 'function' then
    func = argc
    argc = 1
  end
  local nargs, args = select('#', ...), { ... }
  return check(coroutine.yield(yield_marker, function(callback)
    args[argc] = function(...)
      callback(nil, ...)
    end
    nargs = math.max(nargs, argc)
    return func(unpack(args, 1, nargs))
  end))
end

--- Creates an async function with a callback style function.
--- @param argc integer The number of arguments of func. Must be included.
--- @param func function A callback style function to be converted. The last argument must be the callback.
--- @return async fun(...)
--- @overload fun(func: function): async fun()
function M.wrap(argc, func)
  if type(argc) == 'function' then
    func = argc
    argc = 1
  end
  assert(type(argc) == 'number')
  assert(type(func) == 'function')
  --- @async
  return function(...)
    return M.await(argc, func, ...)
  end
end

--- An async function that when called will yield to the Neovim scheduler to be
--- able to call the API.
M.scheduler = M.wrap(vim.schedule)

--- Abandon an async thread
M.kill = M.wrap(function() end)

local TARGET_MIN_FPS = 120
local TARGET_FRAME_TIME_NS = 10 ^ 9 / TARGET_MIN_FPS

--- Automatically yield an async thread after a certain
--- amount of time.
--- @async
--- @param start_time integer
--- @return integer new_start_time
function M.event_control(start_time)
  local duration = vim.uv.hrtime() - start_time
  if duration > TARGET_FRAME_TIME_NS then
    M.scheduler()
    return vim.uv.hrtime()
  end
  return start_time
end

--- Async version of `ipairs` which internally calls async.event_control between
--- iterations.
--- @async
--- @generic T
--- @param a T[]
--- @return fun(): integer, T
--- @return any
--- @return integer
function M.ipairs(a)
  local start_time = vim.uv.hrtime()

  --- @async
  --- @param i integer
  --- @return integer?, any?
  local function iter(_, i)
    start_time = M.event_control(start_time)

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
--- @async
--- @generic K, V
--- @param t table<K, V>
--- @return fun(): K, V
--- @return any
--- @return K?
function M.pairs(t)
  local start_time = vim.uv.hrtime()

  --- @async
  local function iter(_, k)
    start_time = M.event_control(start_time)
    return next(t, k)
  end

  return iter, t, nil
end

return M
