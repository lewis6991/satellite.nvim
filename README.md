# nvim-scrollview

`nvim-scrollview` is a Neovim plugin that displays a (non-interactive) scrollbar.
The plugin is customizable (see `:help scrollview-configuration`).

<img src="screencast.gif?raw=true" width="800"/>

## Requirements

* `nvim>=0.5`

## Installation

A package manager can be used to install `nvim-scrollview`.
<details><summary>Examples</summary><br>

* [Vim8 packages][vim8pack]:
  - `git clone https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/pack/plugins/start/nvim-scrollview`
* [Vundle][vundle]:
  - Add `Plugin 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - `:PluginInstall` or `$ vim +PluginInstall +qall`
* [Pathogen][pathogen]:
  - `git clone --depth=1 https://github.com/dstein64/nvim-scrollview ~/.local/share/nvim/site/bundle/nvim-scrollview`
* [vim-plug][vimplug]:
  - Add `Plug 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - `:PlugInstall` or `$ vim +PlugInstall +qall`
* [dein.vim][dein]:
  - Add `call dein#add('dstein64/nvim-scrollview')` to `~/.config/nvim/init.vim`
  - `:call dein#install()`
* [NeoBundle][neobundle]:
  - Add `NeoBundle 'dstein64/nvim-scrollview'` to `~/.config/nvim/init.vim`
  - Re-open vim or execute `:source ~/.config/nvim/init.vim`

</details>

## Usage

TODO TODO TODO

## Documentation

Documentation can be accessed with:

```vim
:help nvim-scrollview
```

The underlying markup is in [scrollview.txt](doc/scrollview.txt).

There is documentation on the following topics.

TODO TODO TODO

License
-------

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
