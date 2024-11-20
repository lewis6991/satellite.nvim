--- This module implements a user autocmd for Search events
---
--- The data fields is populated depending on the specific search event:
--- - 'key' is set to the key pressed for n,N,& and * events
--- - 'hlsearch' is set to the current value when v:hlsearch changes
--- - 'pattern' is set to the current search pattern when a new search is
---    performed
---

local api, fn = vim.api, vim.fn

--- @param data any
local function exec_autocmd(data)
  api.nvim_exec_autocmds('User', { pattern = 'Search', data = data })
end

local last_hlsearch = vim.v.hlsearch

local timer = assert(vim.loop.new_timer())

-- default value of 'updatetime' is too long (4s). Make it 1s at most.
local interval = math.min(vim.o.updatetime, 1000)

timer:start(0, interval, function()
  -- Regularly check v:hlsearch
  if vim.v.hlsearch ~= last_hlsearch then
    last_hlsearch = vim.v.hlsearch
    vim.schedule(function()
      exec_autocmd { hlsearch = last_hlsearch }
    end)
  end
end)

vim.on_key(function(key)
  if api.nvim_get_mode().mode == 'n' and key:match('[nN&*]') then
    exec_autocmd { key = key }
  end
end)

--- @return boolean
local function is_search_mode()
  return vim.o.incsearch
    and vim.o.hlsearch
    and api.nvim_get_mode().mode == 'c'
    and vim.tbl_contains({ '/', '?' }, fn.getcmdtype())
end

local group = api.nvim_create_augroup('satellite_autocmd_search', {})

api.nvim_create_autocmd({ 'CmdlineEnter', 'CmdLineChanged', 'CmdlineLeave' }, {
  group = group,
  callback = function()
    if is_search_mode() then
      exec_autocmd { pattern = fn.getcmdline() }
    end
  end,
})
