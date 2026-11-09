local t = require('test.testutil')
local eq, ok = t.eq, t.ok
local n = require('test.functional.testnvim')()
local exec_lua = n.exec_lua

local function diagnostic_marks()
  n.poke_eventloop()
  return exec_lua(function()
    local ns = vim.api.nvim_get_namespaces()['satellite.Handler.diagnostic']
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winid).relative == 'win' then
        local result = {}
        local bufnr = vim.api.nvim_win_get_buf(winid)
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
          local text = assert(mark[4]).virt_text
          if text and text[1] then
            result[#result + 1] = { mark[2], text[1][1], text[1][2] }
          end
        end
        return result
      end
    end
    return {}
  end)
end

describe('diagnostic scrollbars', function()
  before_each(function()
    n.clear()
    exec_lua(function(root)
      vim.opt.runtimepath:prepend(root)
      vim.o.lines = 24
      vim.o.columns = 80
      vim.diagnostic.config({
        virtual_text = false,
        virtual_lines = false,
        signs = false,
        underline = false,
      })
      local lines = {}
      for i = 1, 200 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      require('satellite').setup()
    end, vim.env.SATELLITE_TEST_ROOT)
    n.poke_eventloop()
  end)

  it('updates a hidden buffer when shown without refreshing the current scrollbar', function()
    local hidden = exec_lua(function()
      local view = require('satellite.view')
      local refresh = view.refresh_bars
      vim.g.satellite_test_refreshes = 0
      view.refresh_bars = function()
        vim.g.satellite_test_refreshes = vim.g.satellite_test_refreshes + 1
        refresh()
      end
      local bufnr = vim.api.nvim_create_buf(true, false)
      local lines = {}
      for i = 1, 200 do
        lines[i] = 'Hidden line ' .. i
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      local ns = vim.api.nvim_create_namespace('test.hidden')
      vim.diagnostic.set(
        ns,
        bufnr,
        { { lnum = 100, col = 0, message = 'old warning', severity = 2 } }
      )
      vim.diagnostic.set(
        ns,
        bufnr,
        { { lnum = 100, col = 0, message = 'new error', severity = 1 } }
      )
      return bufnr
    end)
    n.poke_eventloop()
    eq(0, exec_lua('return vim.g.satellite_test_refreshes'))
    eq({}, diagnostic_marks())

    n.command('buffer ' .. hidden)
    local marks = diagnostic_marks()
    eq(1, #marks)
    eq('SatelliteDiagnosticError', marks[1][3])
  end)

  it('releases cached diagnostics when their buffer is wiped', function()
    local retained = exec_lua(function()
      local bufnr = vim.api.nvim_get_current_buf()
      local get = vim.diagnostic.get
      local copies = setmetatable({}, { __mode = 'v' })
      vim.diagnostic.get = function(buf, opts)
        local result = get(buf, opts)
        if buf == bufnr then
          copies[1] = result
        end
        return result
      end
      local ns = vim.api.nvim_create_namespace('test.cache')
      vim.diagnostic.set(ns, bufnr, { { lnum = 100, col = 0, message = 'warning', severity = 2 } })
      require('satellite.view').refresh_bars()
      collectgarbage('collect')
      local before = copies[1] ~= nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
      collectgarbage('collect')
      return { before, copies[1] ~= nil }
    end)
    eq({ true, false }, retained)
  end)

  it('renders many unsorted diagnostics without repeatedly scanning the whole buffer', function()
    exec_lua(function()
      local lines = {}
      for i = 1, 10000 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      local first, second = {}, {} --- @type vim.Diagnostic.Set[], vim.Diagnostic.Set[]
      for i = 1000, 1, -1 do
        local diags = i % 2 == 0 and first or second
        diags[#diags + 1] = { lnum = i * 9, col = 0, message = 'warning', severity = 2 }
      end
      local height = vim.api.nvim_win_text_height
      vim.g.satellite_test_scanned_rows = 0
      vim.api.nvim_win_text_height = function(winid, opts)
        local start_row = opts.start_row or 0
        local end_row = opts.end_row
          or vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid)) - 1
        vim.g.satellite_test_scanned_rows = vim.g.satellite_test_scanned_rows
          + end_row
          - start_row
          + 1
        return height(winid, opts)
      end
      vim.diagnostic.set(vim.api.nvim_create_namespace('test.first'), 0, first)
      vim.diagnostic.set(vim.api.nvim_create_namespace('test.second'), 0, second)
    end)
    local marks = t.retry(nil, 2000, function()
      local result = diagnostic_marks()
      ok(#result > 10)
      return result
    end)
    for _, mark in ipairs(marks) do
      eq('≡', mark[2])
      eq('SatelliteDiagnosticWarn', mark[3])
    end
    -- Allow refreshes for text and diagnostic changes, but not a prefix scan
    -- for each diagnostic.
    local scanned = exec_lua('return vim.g.satellite_test_scanned_rows')
    ok(scanned < 10000 * 10, 'fewer than 100000 scanned rows', scanned)
  end)

  it('places diagnostics around folds, wrapped lines and virtual lines', function()
    local expected = exec_lua(function()
      vim.wo.foldmethod = 'manual'
      vim.api.nvim_buf_set_lines(0, 24, 25, false, { string.rep('x', 240) })
      vim.cmd('30,80fold')
      local virtual_lines = {}
      for _ = 1, 10 do
        virtual_lines[#virtual_lines + 1] = { { 'virtual line' } }
      end
      vim.api.nvim_buf_set_extmark(0, vim.api.nvim_create_namespace('test.virtual'), 90, 0, {
        virt_lines = virtual_lines,
        virt_lines_above = true,
      })
      local winid = vim.api.nvim_get_current_win()
      local util = require('satellite.util')
      util.invalidate_virtual_line_count_cache(winid)
      local expected_marks = {}
      for _, item in ipairs({ { 4, '-' }, { 39, '=' }, { 149, '-' }, { 189, '-' } }) do
        expected_marks[#expected_marks + 1] = {
          util.row_to_barpos(winid, item[1]),
          item[2],
          'SatelliteDiagnosticWarn',
        }
      end
      local diags = {}
      for _, row in ipairs({ 189, 59, 4, 149, 39 }) do
        diags[#diags + 1] = { lnum = row, col = 0, message = 'warning', severity = 2 }
      end
      vim.diagnostic.set(vim.api.nvim_create_namespace('test.layout'), 0, diags)
      return expected_marks
    end)
    eq(expected, diagnostic_marks())
  end)
end)
