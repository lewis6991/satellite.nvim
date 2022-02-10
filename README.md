# nvim-scrollview (fork)

EDIT: This is a heavy fork which removes many features from the original version.

`nvim-scrollview` is a Neovim plugin that displays interactive vertical
scrollbars. The plugin is customizable (see `:help scrollview-configuration`).

<img src="https://github.com/dstein64/media/blob/main/nvim-scrollview/screencast.gif?raw=true" width="643" />

## Features

* Handling for folds
* Scrollbars can be dragged with the mouse

## Requirements

* `nvim>=0.7`

## Installation

[packer.nvim][packer]:
```lua
use 'dstein64/nvim-scrollview'
```

## Usage

* `nvim-scrollview` works automatically, displaying interactive scrollbars.
* The `:ScrollViewDisable` command disables scrollbars.
* The `:ScrollViewEnable` command enables scrollbars. This is only necessary
  if scrollbars have previously been disabled.
* The `:ScrollViewRefresh` command refreshes the scrollbars. This is relevant
  when the scrollbars are out-of-sync, which can occur as a result of some
  window arrangement actions.
* The scrollbars can be dragged.

## Configuration

There are various settings that can be configured. Please see the documentation
for details.

* File types for which scrollbars should not be displayed
  - `scrollview_excluded_filetypes`
* Scrollbar color and transparency level
  - `ScrollView` highlight group
  - `scrollview_winblend`
* Whether scrollbars should be displayed in all windows, or just the current
  window
  - `scrollview_current_only`
* A character to display on scrollbars
  - `scrollview_character`

## Documentation

Documentation can be accessed with:

```nvim
:help nvim-scrollview
```

The underlying markup is in [scrollview.txt](doc/scrollview.txt).

## License

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[packer]: https://github.com/wbthomason/packer.nvim
