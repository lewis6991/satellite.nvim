local t = require('test.testutil')
local eq, ok = t.eq, t.ok
local n = require('test.functional.testnvim')()
local exec_lua = n.exec_lua

local function get_bar_windows()
  n.poke_eventloop()
  return exec_lua(function()
    local bars = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winid).relative == 'win' then
        bars[#bars + 1] = winid
      end
    end
    return bars
  end)
end

local function get_state()
  return {
    bars = #get_bar_windows(),
    notifications = exec_lua('return vim.g.satellite_test_notifications'),
  }
end

describe('scrollbars', function()
  before_each(function()
    n.clear()
    exec_lua(function(root)
      vim.opt.runtimepath:prepend(root)
      vim.o.lines = 24
      vim.o.columns = 80
      local notifications = {} --- @type string[]
      vim.g.satellite_test_notifications = notifications
      vim.notify = function(message)
        table.insert(notifications, message)
        vim.g.satellite_test_notifications = notifications
      end

      local lines = {}
      for i = 1, 200 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd.redraw()
    end, vim.env.SATELLITE_TEST_ROOT)
  end)

  it('shows a scrollbar for a long buffer', function()
    exec_lua(function()
      require('satellite').setup()
    end)
    eq({ bars = 1, notifications = {} }, get_state())
  end)

  it('shows mini.diff additions, changes and deletions in the scrollbar', function()
    exec_lua(function()
      package.loaded['mini.diff'] = {
        get_buf_data = function(_)
          return {
            hunks = {
              { type = 'add', buf_start = 10, buf_count = 1 },
              { type = 'change', buf_start = 100, buf_count = 2 },
              { type = 'delete', buf_start = 200, buf_count = 0 },
            },
          }
        end,
      }
      require('satellite.handlers.minidiff')
      require('satellite').setup()
    end)
    eq({ bars = 1, notifications = {} }, get_state())

    local signs = exec_lua(function(winid)
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local ns = vim.api.nvim_get_namespaces()['satellite.Handler.minidiff']
      local result = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
        local details = assert(mark[4])
        result[#result + 1] = { details.sign_text, details.sign_hl_group }
      end
      return result
    end, get_bar_windows()[1])
    eq({
      { ' │', 'SatelliteMiniDiffAdd' },
      { ' │', 'SatelliteMiniDiffChange' },
      { ' -', 'SatelliteMiniDiffDelete' },
    }, signs)
  end)

  it('can load from an expression mapping #96', function()
    exec_lua(function()
      vim.keymap.set('n', 'x', function()
        require('satellite').setup()
        return ''
      end, { expr = true })
      vim.api.nvim_feedkeys('x', 'xt', false)
    end)
    eq({ bars = 1, notifications = {} }, get_state())
  end)

  it('stays disabled when disabled before the initial refresh', function()
    exec_lua(function()
      require('satellite').setup()
      vim.cmd.SatelliteDisable()
    end)
    eq({ bars = 0, notifications = {} }, get_state())
  end)

  it('recreates a scrollbar that was closed', function()
    exec_lua(function()
      require('satellite').setup()
    end)
    eq({ bars = 1, notifications = {} }, get_state())

    local bar = get_bar_windows()[1]
    n.api.nvim_win_close(bar, true)
    n.command('SatelliteRefresh')

    eq({ bars = 1, notifications = {} }, get_state())
    ok(get_bar_windows()[1] ~= bar)
  end)

  it('removes the scrollbar when disabled and restores it when enabled', function()
    exec_lua(function()
      require('satellite').setup()
    end)
    eq({ bars = 1, notifications = {} }, get_state())

    n.command('SatelliteDisable')
    eq({ bars = 0, notifications = {} }, get_state())

    n.command('SatelliteEnable')
    eq({ bars = 1, notifications = {} }, get_state())

    n.command('SatelliteEnable')
    n.command('SatelliteRefresh')
    eq({ bars = 1, notifications = {} }, get_state())
  end)

  it('moves the scrollbar highlight when scrolling down and back up', function()
    local function highlighted_rows()
      return exec_lua(function(winid)
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local ns = vim.api.nvim_get_namespaces().satellite
        local rows = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
          local chunks = assert(mark[4]).virt_text
          if chunks and chunks[1] and chunks[1][2] == 'SatelliteBar' then
            rows[#rows + 1] = mark[2]
          end
        end
        return rows
      end, get_bar_windows()[1])
    end

    exec_lua(function()
      require('satellite').setup()
    end)
    eq({ bars = 1, notifications = {} }, get_state())
    local top = highlighted_rows()
    eq(0, top[1])

    n.feed('G')
    local bottom = highlighted_rows()
    ok(#bottom > 0)
    ok(bottom[1] > top[#top])

    n.feed('gg')
    eq(top, highlighted_rows())
    eq({ bars = 1, notifications = {} }, get_state())
  end)

  it('keeps the scrollbar in the current split with current_only', function()
    exec_lua(function()
      require('satellite').setup({ current_only = true })
    end)
    eq({ bars = 1, notifications = {} }, get_state())
    local first = n.api.nvim_get_current_win()
    eq(first, n.api.nvim_win_get_config(get_bar_windows()[1]).win)

    n.command('vsplit')
    local second = n.api.nvim_get_current_win()
    eq({ bars = 1, notifications = {} }, get_state())
    eq(second, n.api.nvim_win_get_config(get_bar_windows()[1]).win)

    n.api.nvim_set_current_win(first)
    eq({ bars = 1, notifications = {} }, get_state())
    eq(first, n.api.nvim_win_get_config(get_bar_windows()[1]).win)
  end)
end)
