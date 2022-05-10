WIP

# satellite.nvim

`satellite.nvim` is a Neovim plugin that displays decorated scrollbars.

## Features

* Display marks for different kinds of decorations across the buffer. Builtin handlers include:
  * search results
  * diagnostic
  * Git hunks (via [gitsigns.nvim])
* Handling for folds
* Mouse support (currently broken)

## Requirements

Neovim >= 0.7.0

## Installation

[packer.nvim]:
```lua
use 'lewis6991/satellite.nvim'
```

## Usage

For basic setup with all batteries included:
```lua
require('satellite').setup()
```

If using [packer.nvim] Satellite can be setup directly in the plugin spec:

```lua
use {
  'lewis6991/satellite.nvim',
  config = function()
    require('satellite').setup()
  end
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

TODO

## Documentation

Documentation can be accessed with:

```nvim
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
[packer.nvim]: https://github.com/wbthomason/packer.nvim
