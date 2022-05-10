WIP

# satellite.nvim

`satellite.nvim` is a Neovim plugin that displays decorated scrollbars.

## Features

* Display marks for different kinds of decorations across the buffer. Builtin handlers include:
  * search results
  * diagnostic
  * Git hunks (via Gitsigns)
* Handling for folds
* Mouse support (currently broken)

## Requirements

Neovim >= 0.7.0

## Installation

[packer.nvim][packer]:
```lua
use 'lewis6991/satellite.nvim'
```

## Usage

For basic setup with all batteries included:
```lua
require('satellite').setup()
```

If using [packer.nvim][packer] Satellite can be setup directly in the plugin spec:

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

[packer]: https://github.com/wbthomason/packer.nvim
