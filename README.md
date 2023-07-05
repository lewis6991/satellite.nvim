# satellite.nvim

`satellite.nvim` is a Neovim plugin that displays decorated scrollbars.

![image](https://user-images.githubusercontent.com/7904185/167670068-8660fe2e-eb5a-45df-912d-479eb43e0239.png)

**NOTE**: Many API's required to implement a decorated scrollbar in Neovim do not yet exist,
and because of this, this plugin implements fairly unideal and unoptimised workarounds to get desired behaviours.

## Features

* Display marks for different kinds of decorations across the buffer. Builtin handlers include:
  * Cursor
  * Search results
  * Diagnostic
  * Git hunks (via [gitsigns.nvim])
  * Marks
* Handling for folds
* Mouse support

## Requirements

Neovim nightly

## Usage

For basic setup with all batteries included:
```lua
require('satellite').setup()
```

Configuration can be passed to the setup function. Here is an example with most of
the default settings:

```lua
require('satellite').setup {
  current_only = false,
  winblend = 50,
  zindex = 40,
  excluded_filetypes = {},
  width = 2,
  handlers = {
    cursor = {
      enable = true,
    },
    search = {
      enable = true,
    },
    diagnostic = {
      enable = true,
      signs = {'-', '=', '≡'},
      min_severity = vim.diagnostic.severity.HINT,
    },
    gitsigns = {
      enable = true,
      signs = { -- can only be a single character (multibyte is okay)
        add = "│",
        change = "│",
        delete = "-",
      },
    },
    marks = {
      enable = true,
      show_builtins = false, -- shows the builtin marks like [ ] < >
    },
  },
}
```

* The `:SatelliteDisable` command disables scrollbars.
* The `:SatelliteEnable` command enables scrollbars. This is only necessary
  if scrollbars have previously been disabled.
* The `:SatelliteRefresh` command refreshes the scrollbars. This is relevant
  when the scrollbars are out-of-sync, which can occur as a result of some
  window arrangement actions.

## Configuration

There are various settings that can be configured. Please see the documentation
for details.

## Handlers

Satellite provides an API to implement handlers for the scrollbar, see [HANDLERS](HANDLERS.md) for more details.

## Documentation

Documentation can be accessed with:

```vim
:help satellite
```

## Credit

This plugin was based on [nvim-scrollview] which provides a very good implementation for a normal scrollbar.

## Similar plugins

- [nvim-scrollview]
- [nvim-scrollbar]

[gitsigns.nvim]: https://github.com/lewis6991/gitsigns.nvim
[nvim-scrollbar]: https://github.com/petertriho/nvim-scrollbar
[nvim-scrollview]: https://github.com/dstein64/nvim-scrollview
