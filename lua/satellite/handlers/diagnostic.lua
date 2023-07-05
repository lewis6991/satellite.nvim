local api = vim.api

local util = require 'satellite.util'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'SatelliteDiagnosticError',
  [vim.diagnostic.severity.WARN] = 'SatelliteDiagnosticWarn',
  [vim.diagnostic.severity.INFO] = 'SatelliteDiagnosticInfo',
  [vim.diagnostic.severity.HINT] = 'SatelliteDiagnosticHint',
}

---@type Handler
local handler = {
  name = 'diagnostic',
}

local function setup_hl()
  for _, sfx in ipairs {'Error', 'Warn', 'Info', 'Hint' } do
    api.nvim_set_hl(0, 'SatelliteDiagnostic' .. sfx, {
      default = true,
      link = 'Diagnostic' .. sfx
    })
  end
end

--- @class DiagnosticConfig: HandlerConfig
--- @field signs string[]
--- @field min_severity integer
local config = {
  enable = true,
  overlap = true,
  priority = 50,
  signs = { '-', '=', '≡' },
  min_severity = vim.diagnostic.severity.HINT,
}

function handler.setup(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)
  handler.config = config

  local group = api.nvim_create_augroup('satellite_diagnostics', {})

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_hl,
  })

  setup_hl()

  api.nvim_create_autocmd('DiagnosticChanged', {
    group = group,
    callback = update,
  })
end

function handler.update(bufnr, winid)
  local marks = {} ---@type {count: integer, severity: integer}[]
  local diags = vim.diagnostic.get(bufnr)
  for _, diag in ipairs(diags) do
    if diag.severity <= config.min_severity then
      local pos = util.row_to_barpos(winid, diag.lnum)

      local count = 1
      if marks[pos] and marks[pos].count then
        count = marks[pos].count + 1
      end

      local severity = diag.severity or vim.diagnostic.severity.HINT
      if marks[pos] and marks[pos].severity and marks[pos].severity < severity then
        severity = marks[pos].severity
      end

      marks[pos] = {
        count = count,
        severity = severity,
      }
    end
  end

  local ret = {} ---@type SatelliteMark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      highlight = diagnostic_hls[mark.severity],
      symbol = config.signs[mark.count] or config.signs[#config.signs],
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
