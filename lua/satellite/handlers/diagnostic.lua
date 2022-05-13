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
      require('satellite').refresh_bars()
    end
  })
end

function handler.update(bufnr)
  local marks = {}
  local diags = vim.diagnostic.get(bufnr)
  for _, diag in ipairs(diags) do
    marks[#marks+1] = {
      lnum = diag.lnum + 1,
      symbol = {'-', '=', '≡'},
      -- symbol = {'⠂', '⠅', '⠇', '⠗', '⠟', '⠿'},
      highlight = diagnostic_hls[diag.severity]
    }
  end
  return marks
end

require('satellite.handlers').register(handler)
