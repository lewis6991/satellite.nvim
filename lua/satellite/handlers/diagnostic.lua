local util = require'satellite.util'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
  [vim.diagnostic.severity.WARN]  = 'DiagnosticWarn',
  [vim.diagnostic.severity.INFO]  = 'DiagnosticInfo',
  [vim.diagnostic.severity.HINT]  = 'DiagnosticHint',
}

---@type Handler
local handler = {
  name = 'diagnostic'
}

function handler.init()
  local gid = vim.api.nvim_create_augroup('satellite_diagnostics', {})
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = gid,
    callback = function()
      require('satellite.view').refresh_bars()
    end
  })
end

local SYMBOLS = {'-', '=', '≡'}
-- local SYMBOLS = {'⠂', '⠅', '⠇', '⠗', '⠟', '⠿'},

function handler.update(bufnr, winid)
  local marks = {} ---@type {count: integer, highlight: string}[]
  local diags = vim.diagnostic.get(bufnr)
  for _, diag in ipairs(diags) do
    local lnum = diag.lnum + 1
    local pos = util.row_to_barpos(winid, lnum-1)

    local count = 1
    if marks[pos] and marks[pos].count then
      count = marks[pos].count + 1
    end

    marks[pos] = {
      count = count,
      highlight = diagnostic_hls[diag.severity]
    }
  end

  local ret = {} ---@type SatelliteMark[]

  for pos, mark in pairs(marks) do
    ret[#ret+1] = {
      pos = pos,
      highlight = mark.highlight,
      symbol = SYMBOLS[mark.count] or SYMBOLS[#SYMBOLS]
    }
  end

  return ret
end

require('satellite.handlers').register(handler)
