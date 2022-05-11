
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

return M
