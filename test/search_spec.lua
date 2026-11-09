local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')
local eq = t.eq

for _, direction in ipairs({ '/', '?' }) do
  it('updates visible search marks after each edit to ' .. direction .. ' #58', function()
    n.clear()
    local screen = Screen.new(80, 24)
    n.exec_lua(function(root)
      vim.opt.runtimepath:prepend(root)
      vim.o.incsearch = true
      vim.o.hlsearch = true
      local lines = {} --- @type string[]
      for i = 1, 200 do
        lines[i] = 'Line ' .. i
      end
      lines[20] = 'foo'
      lines[100] = 'fob'
      lines[180] = 'far'
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      require('satellite').setup()
    end, vim.env.SATELLITE_TEST_ROOT)

    --- @param count integer
    --- @param unchanged? boolean
    local function expect_marks(count, unchanged)
      screen:expect({
        unchanged = unchanged,
        condition = function()
          -- The cursor marker covers the current match; count the other matches.
          local _, actual = screen:get_snapshot().grid:gsub('⠂', '')
          eq(count, actual)
        end,
      })
    end

    expect_marks(0, true)
    n.feed(direction .. 'f')
    expect_marks(2)
    n.feed('o')
    expect_marks(1)
    n.feed('<BS>')
    expect_marks(2)
    n.feed('x')
    expect_marks(0)
    n.feed('<BS>')
    expect_marks(2)
    n.feed('<BS>')
    expect_marks(0)
    n.feed('f')
    expect_marks(2)
    n.feed('<Esc>')
    screen:detach()
  end)
end
