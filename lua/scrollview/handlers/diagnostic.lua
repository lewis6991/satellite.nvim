local diagnostic_hls = {
  [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
  [vim.diagnostic.severity.WARN]  = 'DiagnosticWarn',
  [vim.diagnostic.severity.INFO]  = 'DiagnosticInfo',
  [vim.diagnostic.severity.HINT]  = 'DiagnosticHint',
}

local gid = vim.api.nvim_create_augroup('scrollview_diagnostics', {})
vim.api.nvim_create_autocmd('DiagnosticChanged', {
  group = gid,
  callback = function()
    require('scrollview').refresh_bars()
  end
})

require('scrollview.handlers').register('diagnostics', function(bufnr)
  local marks = {}
  local diags = vim.diagnostic.get(bufnr)
  for _, diag in ipairs(diags) do
    marks[#marks+1] = {
      lnum = diag.lnum,
      symbol = '─',
      highlight = diagnostic_hls[diag.severity]
    }
  end
  return marks
end)
