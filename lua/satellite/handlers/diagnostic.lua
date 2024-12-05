local api = vim.api

local util = require 'satellite.util'
local async = require 'satellite.async'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'SatelliteDiagnosticError',
  [vim.diagnostic.severity.WARN] = 'SatelliteDiagnosticWarn',
  [vim.diagnostic.severity.INFO] = 'SatelliteDiagnosticInfo',
  [vim.diagnostic.severity.HINT] = 'SatelliteDiagnosticHint',
}

--- @type Satellite.Handler
local handler = {
  name = 'diagnostic',
}

local function setup_hl()
  for _, sfx in ipairs { 'Error', 'Warn', 'Info', 'Hint' } do
    api.nvim_set_hl(0, 'SatelliteDiagnostic' .. sfx, {
      default = true,
      link = 'Diagnostic' .. sfx,
    })
  end
end

--- @class Satellite.Handlers.DiagnosticConfig: Satellite.Handlers.BaseConfig
--- @field signs string[]
--- @field min_severity integer
local config = {
  enable = true,
  overlap = true,
  priority = 50,
  signs = {
    error = { '-', '=', '≡' },
    warn = { '-', '=', '≡' },
    info = { '-', '=', '≡' },
    hint = { '-', '=', '≡' },
  },
  min_severity = vim.diagnostic.severity.HINT,
}

local buf_diags = {} --- @type table<integer,Diagnostic[]>

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
    callback = function(args)
      --- vim.diagnostic.get() is expensive as it runs vim.deepcopy() on every
      --- call. Keep a local copy that is only updated when diagnostics change.
      local bufnr = args.buf
      buf_diags[bufnr] = args.data.diagnostics

      vim.schedule(update)
    end,
  })
end

local function get_mark(severity, count)
  -- Backward compatibility
  if config.signs[1] then
    return config.signs[count] or config.signs[#config.signs]
  end

  -- Per severity signs
  local diag_type = 'hint'
  if severity == vim.diagnostic.severity.ERROR then
    diag_type = 'error'
  elseif severity == vim.diagnostic.severity.WARN then
    diag_type = 'warn'
  elseif severity == vim.diagnostic.severity.INFO then
    diag_type = 'info'
  elseif severity == vim.diagnostic.severity.HINT then
    diag_type = 'hint'
  end
  return config.signs[diag_type][count] or config.signs[diag_type][#config.signs[diag_type]]
end

function handler.update(bufnr, winid)
  local marks = {} --- @type {count: integer, severity: integer}[]
  local diags = buf_diags[bufnr] or {}
  local pred = async.winbuf_pred(bufnr, winid)
  for _, diag in async.ipairs(diags, pred) do
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

  local ret = {} --- @type Satellite.Mark[]

  for pos, mark in pairs(marks) do
    ret[#ret + 1] = {
      pos = pos,
      highlight = diagnostic_hls[mark.severity],
      symbol = get_mark(mark.severity, mark.count),
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
