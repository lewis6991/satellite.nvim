local util = require 'satellite.util'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
  [vim.diagnostic.severity.WARN] = 'DiagnosticWarn',
  [vim.diagnostic.severity.INFO] = 'DiagnosticInfo',
  [vim.diagnostic.severity.HINT] = 'DiagnosticHint',
}

---@type Handler
local handler = {
  name = 'diagnostic',
}

local config = {
  signs = { '-', '=', '≡' },
  min_severity = vim.diagnostic.severity.HINT,
}

function handler.init(config0, update)
  config = vim.tbl_deep_extend('force', config, config0)

  local gid = vim.api.nvim_create_augroup('satellite_diagnostics', {})
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = gid,
    callback = update,
  })
end

function handler.update(bufnr, winid)
  local marks = {} ---@type {count: integer, severity: integer}[]
  local diags = vim.diagnostic.get(bufnr)
  for _, diag in ipairs(diags) do
    if diag.severity <= config.min_severity then
      local lnum = diag.lnum + 1
      local pos = util.row_to_barpos(winid, lnum - 1)

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
