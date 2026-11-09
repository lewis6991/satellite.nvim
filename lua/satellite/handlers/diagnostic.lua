local api = vim.api

local util = require 'satellite.util'
local async = require 'satellite.async'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'SatelliteDiagnosticError',
  [vim.diagnostic.severity.WARN] = 'SatelliteDiagnosticWarn',
  [vim.diagnostic.severity.INFO] = 'SatelliteDiagnosticInfo',
  [vim.diagnostic.severity.HINT] = 'SatelliteDiagnosticHint',
}

--- @class satellite.Handler.Diagnostic: Satellite.Handler
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

local buf_diags = {} --- @type table<integer,vim.Diagnostic[]>

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
      buf_diags[args.buf] = nil

      for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        if api.nvim_win_get_buf(winid) == args.buf and util.is_ordinary_window(winid) then
          update()
          break
        end
      end
    end,
  })

  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      buf_diags[args.buf] = nil
    end,
  })
end

--- @param severity integer
--- @param count integer
--- @return string
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
  --- @type table<integer, string?>
  local dsign = assert(config.signs[diag_type])
  return dsign[count] or assert(dsign[#dsign])
end

function handler.update(bufnr, winid)
  local marks = {} --- @type {count: integer, severity: integer}[]
  local diags = buf_diags[bufnr]
  if not diags then
    -- Load a copy only when the buffer is rendered, and sort it for incremental
    -- line counting. vim.diagnostic.get() includes all diagnostic namespaces.
    diags = vim.diagnostic.get(bufnr)
    table.sort(diags, function(a, b)
      return a.lnum < b.lnum
    end)
    buf_diags[bufnr] = diags
  end

  local pred = util.winbuf_pred(bufnr, winid)
  local map_row --- @type (fun(row: integer): integer)?
  for _, diag in async.ipairs(diags) do
    if pred() == false then
      return {}
    end
    if diag.severity <= config.min_severity then
      map_row = map_row or util.row_to_barpos_mapper(winid)
      local pos = map_row(diag.lnum)

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
      highlight = assert(diagnostic_hls[mark.severity]),
      symbol = get_mark(mark.severity, mark.count),
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
