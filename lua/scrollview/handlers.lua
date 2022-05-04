local M = {
  handlers = {}
}

function M.register(name, handler)
  M.handlers[name] = handler
end

return M
