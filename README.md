# nvim-scrollview

`nvim-scrollview` is a Neovim plugin that displays interactive scrollbars.
The plugin is customizable (see `:help scrollview-configuration`).

<img src="screencast.gif?raw=true" width="640"/>

## Requirements

* `nvim>=0.5`

## Installation

A package manager can be used to install `nvim-scrollview`.
<details><summary>Examples</summary><br>

* [Vim8 packages][vim8pack]:
  - `git clone https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/pack/plugins/start/nvim-scrollview`
* [Vundle][vundle]:
  - Add `Plugin 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - `:PluginInstall` or `$ nvim +PluginInstall +qall`
* [Pathogen][pathogen]:
  - `git clone --depth=1 https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/bundle/nvim-scrollview`
* [vim-plug][vimplug]:
  - Add `Plug 'dstein64/nvim-scrollview', { 'branch': 'main' }` to `~/.config/nvim/init.vim`
  - `:PlugInstall` or `$ nvim +PlugInstall +qall`
* [dein.vim][dein]:
  - Add `call dein#add('dstein64/nvim-scrollview')` to `~/.config/nvim/init.vim`
  - `:call dein#install()`
* [NeoBundle][neobundle]:
  - Add `NeoBundle 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - Re-open Neovim or execute `:source ~/.config/nvim/init.vim`
* [Packer][packer]:
  - Add `use {'dstein64/nvim-scrollview', branch = 'main' }` to `~/.config/nvim/init.lua`
  - `:PackerInstall`

</details>

## Usage

* `nvim-scrollview` works automatically, displaying interactive scrollbars.
* The `:ScrollViewDisable` command disables scrollbars.
* The `:ScrollViewEnable` command enables scrollbars. This is only necessary
  if scrollbars have previously been disabled.
* The `:ScrollViewRefresh` command refreshes the scrollbars. This is relevant
  when the scrollbars are out-of-sync, which can occur as a result of some
  window arrangement actions.

## Configuration

There are various settings that can be configured.

* Whether scrollbars are enabled or disabled on startup
  - `scrollview_on_startup`
* File types for which scrollbars should not be displayed
  - `scrollview_excluded_filetypes`
* Scrollbar color and transparency level
  - `ScrollView` highlight group
  - `scrollview_winblend`
* Whether scrollbars should be displayed in all windows, or just the current
  window
  - `scrollview_current_only`
* What the scrollbar position and size correspond to (corresponds to how folds
  are accounted for)
  - `scrollview_mode`
* Scrollbar anchor column and offset
  - `scrollview_base`
  - `scrollview_column`
* Whether a mapping is automatically created for mouse support
  - `scrollview_auto_mouse`

Please see the documentation for details.

## Documentation

Documentation can be accessed with:

```nvim
:help nvim-scrollview
```

The underlying markup is in [scrollview.txt](doc/scrollview.txt).

## License

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
[packer]: https://github.com/wbthomason/packer.nvim
