---@class DiagnosticConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer
---@field highlight DiagnosticHighlight
--
---@class DiagnosticHighlight

---@class GitsignsConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer
---@field highlight GitsignsHighlight
--
---@class GitsignsHighlight
---@field add string
---@field delete string
---@field change string

---@class SearchConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer
---@field highlight SearchHighlight
--
---@class SearchHighlight
---@field current_match string
---@field other_matches string

--
---@class MarksConfig
---@field enable boolean
---@field overlap boolean
---@field priority integer
---@field show_builtins boolean
---@field highlight string

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
      highlight = {
        current_match = 'SearchCurrent',
        other_matches = 'Search',
      },
    },
    diagnostic = {
      enable = true,
      overlap = true,
      priority = 50,
      highlight = {
        [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
        [vim.diagnostic.severity.WARN] = 'DiagnosticWarn',
        [vim.diagnostic.severity.INFO] = 'DiagnosticInfo',
        [vim.diagnostic.severity.HINT] = 'DiagnosticHint',
      },
    },
    gitsigns = {
      enable = true,
      overlap = false,
      priority = 20,
      highlight = {
        add = 'GitSignsAdd',
        delete = 'GitSignsDelete',
        change = 'GitSignsChange',
      },
    },
    marks = {
      enable = true,
      overlap = true,
      priority = 60,
      show_builtins = false,
      highlight = 'Normal',
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
  user_config = vim.tbl_deep_extend('force', user_config, config or {})
end

return M
