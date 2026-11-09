local t = require('test.testutil')
local eq, ok = t.eq, t.ok
local n = require('test.functional.testnvim')()
local exec_lua = n.exec_lua

local function get_state()
  n.poke_eventloop()
  return exec_lua(function()
    local winid = vim.api.nvim_get_current_win()
    local props = require('satellite.view').get_props(winid)
    return {
      topline = vim.fn.line('w0'),
      cursor = vim.fn.line('.'),
      bar_row = props and props.row,
      bar_height = props and props.height,
      bar_col = props and props.col,
    }
  end)
end

local function mouse(action, row, col)
  n.api.nvim_input_mouse('left', action, '', 0, row, col)
end

local function click(row, col)
  mouse('press', row, col)
  mouse('release', row, col)
  return get_state()
end

describe('mouse', function()
  before_each(function()
    n.clear()
    exec_lua(function(root)
      vim.opt.runtimepath:prepend(root)
      vim.o.lines = 24
      vim.o.columns = 80
      vim.o.mouse = 'a'

      local lines = {}
      for i = 1, 200 do
        lines[i] = 'Line ' .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      require('satellite').setup()
      vim.cmd.redraw()
    end, vim.env.SATELLITE_TEST_ROOT)
  end)

  it('jumps to the part of the buffer clicked on the scrollbar track', function()
    local before = get_state()
    eq(1, before.topline)

    local after = click(15, before.bar_col)

    ok(after.topline > 1)
    ok(after.bar_row <= 15 and 15 < after.bar_row + after.bar_height)
    ok(after.cursor >= after.topline)
  end)

  it('jumps back to the top when the track is clicked above the scrollbar', function()
    local before = get_state()
    n.feed('G')
    local bottom = get_state()
    ok(bottom.topline > 1)

    local after = click(0, before.bar_col)

    eq(1, after.topline)
  end)

  it('passes a click on the scrollbar itself through as a normal click', function()
    local before = get_state()

    local after = click(before.bar_row + 1, before.bar_col)

    eq(1, after.topline)
    eq(before.bar_row + 2, after.cursor)
  end)

  it('passes a click on the text beside the scrollbar track through', function()
    local before = get_state()

    local after = click(15, before.bar_col - 1)

    eq(1, after.topline)
    eq(16, after.cursor)
  end)

  it('still scrolls when the scrollbar is dragged', function()
    local before = get_state()

    mouse('press', before.bar_row, before.bar_col)
    for row = before.bar_row + 1, 15 do
      mouse('drag', row, before.bar_col)
    end
    mouse('release', 15, before.bar_col)

    ok(get_state().topline > 1)
  end)
end)
