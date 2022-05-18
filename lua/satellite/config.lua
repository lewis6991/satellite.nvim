---@class DiagnosticConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer

---@class GitsignsConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer

---@class SearchConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer

---@class HandlerConfigs
---@field diagnostic DiagnosticConfig
---@field gitsigns GitsignsConfig
---@field search SearchConfig

---@class Config
---@field handlers HandlerConfigs
---@field current_only boolean
---@field winblend integer
---@field zindex integer
---@field excluded_filetypes string[]

local M = {}

---@type Config
local user_config = {
  handlers = {
    search = {
      enable = true,
      overlap = true,
      priority = 10,
    },
    diagnostic = {
      enable = true,
      overlap = true,
      priority = 50,
    },
    gitsigns = {
      enable = true,
      overlap = true,
      priority = 20,
    },
    marks = {
      enable = true,
      show_builtins = false,
    },
  },
  current_only = false,
  winblend = 50,
  zindex = 40,
  excluded_filetypes = {},
}

M.user_config = setmetatable({}, {
  __index = function(_, k)
    return user_config[k]
  end
})

---@param config Config
function M.apply(config)
  user_config = vim.tbl_extend('force', user_config, config or {})
end

return M
