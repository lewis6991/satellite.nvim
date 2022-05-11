
local M = {}

-- NOTE:
-- Workaround for nvim bug where nvim_win_set_option "leaks" local
-- options to windows created afterwards (thanks @sindrets!)
-- SEE:
-- https://github.com/b0o/incline.nvim/issues/4
-- https://github.com/neovim/neovim/issues/18283
-- https://github.com/neovim/neovim/issues/14670
function M.win_set_local_options(win, opts)
  a.nvim_win_call(win, function()
    for opt, val in pairs(opts) do
      local arg
      if type(val) == 'boolean' then
        arg = (val and '' or 'no') .. opt
      else
        arg = opt .. '=' .. val
      end
      vim.cmd('setlocal ' .. arg)
    end
  end)
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

return M
