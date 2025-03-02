--- @class Satellite.Handlers.BaseConfig
---
--- Whether the handler is enabled
--- @field enable boolean
---
--- If `true` decorations are rendered on top of the scrollbar. If `false` the
--- decorations are rendered in a separate column to the right of the scrollbar.
--- @field overlap boolean
---
--- Priority of the decorations from the handler.
--- @field priority integer

--- @class HandlerConfigs
--- @field [string] Satellite.Handlers.BaseConfig
--- @field diagnostic? Satellite.Handlers.DiagnosticConfig
--- @field gitsigns? Satellite.Handlers.GitsignsConfig
--- @field search? Satellite.Handlers.SearchConfig
--- @field marks? Satellite.Handlers.MarksConfig

--- @class SatelliteConfig
--- @field handlers HandlerConfigs
--- @field current_only boolean
--- @field winblend integer
--- @field zindex integer
--- @field excluded_filetypes string[]
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

--- @param config? SatelliteConfig
function M.apply(config)
  user_config = vim.tbl_deep_extend('force', user_config, config or {})
end

return M
