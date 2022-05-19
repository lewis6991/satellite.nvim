local util = require'satellite.util'

local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'DiagnosticErrorSV',
  [vim.diagnostic.severity.WARN] = 'DiagnosticWarnSV',
  [vim.diagnostic.severity.INFO] = 'DiagnosticInfoSV',
  [vim.diagnostic.severity.HINT] = 'DiagnosticHintSV',
}

---@type Handler
local handler = {
  name = 'diagnostic'
}

function handler.init()
  local gid = vim.api.nvim_create_augroup('satellite_diagnostics', {})
  vim.api.nvim_set_hl(0, 'DiagnosticErrorSV', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'DiagnosticWarnSV', { link = 'DiagnosticWarn', default = true })
  vim.api.nvim_set_hl(0, 'DiagnosticInfoSV', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'DiagnosticHintSV', { link = 'DiagnosticHint', default = true })

  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = gid,
    callback = function()
      require('satellite').refresh_bars()
    end
  })
end

local SYMBOLS = {'-', '=', '≡'}
-- local SYMBOLS = {'⠂', '⠅', '⠇', '⠗', '⠟', '⠿'},

function handler.update(bufnr, winid)
  local marks = {}
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

  local ret = {}

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
