# Handlers

Satellite provides an API to implement handlers for the scrollbar.

The API for the handler is as follows:

```lua
--- @class Satellite.Handler
---
--- @field name string
--- Name of the handler
---
--- @field setup fun(config: HandlerConfig, update: fun())
--- Setup the handler and autocmds that are required to trigger the handler.
---
--- @field update fun(bufnr: integer, winid: integer): SatelliteMark[]
--- This function is called when the handler needs to update. It must return
--- a list of SatelliteMark's
---
--- @field enabled fun(): boolean
--- Whether the handler is enabled or not.
---
--- @field config HandlerConfig
```

Handlers can accept any configuration but must also support the following
base class:

```lua
--- @class Satellite.Handlers.BaseConfig
---
--- @field enable boolean
--- Whether the handler is enabled
---
--- @field overlap boolean
--- If `true` decorations are rendered on top of the scrollbar. If `false` the
--- decorations are rendered in a separate column to the right of the scrollbar.
---
--- @field priority integer
--- Priority of the decorations from the handler.
```

The handlers `update()` method returns a list of `Satellite.Mark`'s which is defined as:

```lua
--- @class Satellite.Mark
---
--- @field pos integer
--- Row of the mark, use `require('satellite.util').row_to_barpos(winid, lnum)`
--- to translate an `lnum` from window `winid` to its respective scrollbar row.
---
--- @field highlight string
--- Highlight group of the mark.
---
--- @field symbol string
--- Symbol of the mark. Must be a single character.
---
--- @field unique boolean
--- By default, for each position in the scrollbar, Satellite will only use the
--- last mark with that position. This field indicates the mark is special and
--- must be rendered even if there is another mark at the same position from the
--- handler.
```

To register a handler call:
```lua
require('satellite.handlers').register(handler)
```

Please see the [cursor handler](lua/satellite/handlers/cursor.lua) as an example.
