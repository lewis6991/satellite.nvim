---@class HandlerConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer

---@class HandlerConfigs
---@field [string] HandlerConfig
---@field diagnostic DiagnosticConfig
---@field gitsigns GitsignsConfig
---@field search SearchConfig
---@field marks MarksConfig

---@class SatelliteConfig
---@field handlers HandlerConfigs
---@field current_only boolean
---@field winblend integer
---@field zindex integer
---@field excluded_filetypes string[]
local user_config = {
  handlers = {},
  current_only = false,
  winblend = 50,
  zindex = 40,
  excluded_filetypes = {},
}

local M = {}

--- @type SatelliteConfig
M.user_config = setmetatable({}, {
  __index = function(_, k)
    return user_config[k]
  end,
})

---@param config SatelliteConfig
function M.apply(config)
  user_config = vim.tbl_deep_extend('force', user_config, config or {})
end

return M
