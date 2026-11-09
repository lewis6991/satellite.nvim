assert(#arg >= 2, 'Expected Neovim source directory and test path')
local deps = vim.fs.abspath(table.remove(arg, 1))
arg[1] = vim.fs.abspath(arg[1])
package.path = deps .. '/?.lua;' .. deps .. '/test/?.lua;' .. package.path

-- Neovim's build normally generates these settings.
-- TODO(upstream): Allow Neovim's functional helpers to run without build-generated configuration.
package.preload['test.cmakeconfig.paths'] = function()
  return {
    test_build_dir = deps,
    test_source_path = deps,
    is_asan = false,
    is_zig_build = false,
    translations_enabled = false,
    include_paths = {},
  }
end

vim.env.SATELLITE_TEST_ROOT = vim.uv.cwd()
vim.env.NVIM_PRG = vim.v.progpath
vim.env.NVIM_LOG_FILE = vim.fs.abspath(vim.env.NVIM_LOG_FILE or 'nvim.log')

-- The functional helpers load fixtures relative to Neovim's source directory.
assert(vim.uv.chdir(deps))

-- The harness reads the array part of the command-line arguments.
os.exit(require('test.harness').main(arg --[[@as string[] ]]))
