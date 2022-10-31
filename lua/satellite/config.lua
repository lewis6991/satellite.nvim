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
--
---@class MarksConfig
---@field key    string
---@field enable boolean
---@field overlap boolean
---@field priority integer
---@field show_builtins boolean

---@class HandlerConfigs
---@field diagnostic DiagnosticConfig
---@field gitsigns GitsignsConfig
---@field search SearchConfig
---@field marks MarksConfig

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
      overlap = false,
      priority = 20,
    },
    marks = {
      key = 'm',
      enable = true,
      overlap = true,
      priority = 60,
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
