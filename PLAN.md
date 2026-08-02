# Plan: Window Configuration from XML (NIB-style)

## Goal
Move window configuration (title, dimensions, toolbar, etc.) from Controller.lua
into XML templates — like Xcode NIB/Storyboard files define windows declaratively.

## Design

### XML Format
```xml
<Window title="Mail" width="940" height="520" minWidth="640" minHeight="400">
    <Toolbar>
        <ToolbarItem id="compose" label="Compose"
                     icon="square.and.pencil" tooltip="New Message" />
    </Toolbar>
    <HSplit>
        <List ref="mailboxList" ... />
        ...
    </HSplit>
</Window>
```

All `ns.Window` props become XML attributes:
- `title`, `width`, `height`, `minWidth`, `minHeight`
- `appearance`, `tabbingMode`, `tabbingIdentifier`, `transparentTitlebar`, `hideTitle`, `toolbarLabels`, `visible`
- `sidebar`, `sidebarWidth`, `toolbarContentDividerAfter`, `detail` (workspace mode)

`<Toolbar>` children become `<ToolbarItem>` elements with:
- `id`, `label`, `icon`, `tooltip`, `action`

`action` is a string key that the Controller resolves at runtime (not embedded in XML).

### API Change

`xml.renderFile` signature stays the same but behavior changes when root is `<Window>`:

```lua
-- Before (still works for non-Window XML):
local view, refs = xml.renderFile(path)

-- After (when XML root is <Window>):
local winConfig, content, refs = xml.renderFile(path)
-- winConfig: { title, width, height, minWidth, minHeight, toolbar = {...}, ... }
-- content:   the child view tree (HSplit, VStack, etc.)
-- refs:      named refs from inside the content
```

Controllers then do:
```lua
-- Before:
self.window = ns.Window {
    title  = Model.title,
    width  = Model.windowWidth,
    ...
    layout,
}

-- After:
local cfg, layout, refs = xml.renderFile(VIEWS .. "Window.xml")
self.window = ns.Window(cfg)
-- content is already set via cfg (Window tag handles it)
```

Wait — that won't work because `ns.Window` expects content as positional args or `content` named prop.

Better approach: `xml.renderFile` returns a special table when root is `<Window>`:
```lua
local cfg, content, refs = xml.renderFile(path)
-- cfg.title, cfg.width, cfg.height, cfg.minWidth, cfg.minHeight, cfg.toolbar = {...}
-- cfg.content = content  (the child view tree)
-- Then: ns.Window(cfg) works because Window reads cfg.content
```

Actually simpler: the `<Window>` handler builds the full props table including `content`:

```lua
local cfg, refs = xml.renderFile(path)
-- cfg = { title, width, height, ..., content = <the view tree>, toolbar = {...} }
-- ns.Window(cfg) just works
```

This means `xml.renderFile` returns `(configTable, refs)` when root is `<Window>`,
and `(view, refs)` otherwise (backward compatible).

### Implementation Steps

1. **Add `<Window>` tag to xml registry** (`lua/ui/xml.lua`)
   - Captures all window attributes
   - Separates `<Toolbar>` children from content children
   - `<Toolbar>` → array of toolbar item tables
   - Remaining children → wrapped in VStack if multiple, single child if one
   - Sets `cfg.content` to the wrapped children
   - Returns the config table (not a view)

2. **Add `<Toolbar>` and `<ToolbarItem>` tags**
   - `<Toolbar>` is a passthrough container (consumed by `<Window>`)
   - `<ToolbarItem>` returns a plain table `{ id, label, icon, tooltip }`
   - `action` attribute is a string key (e.g. "compose", "refresh")

3. **Update `xml.render` to detect Window root**
   - After compile, check if single root node is a `<Window>`
   - If so, return `(configTable, refs)` instead of `(view, refs)`
   - Non-Window XML continues to return `(view, refs)` — fully backward compatible

4. **Update Controller.lua files** to use XML window config
   - Each example gets a `views/Window.xml` (or renames existing layout XML)
   - Controller loads window config from XML
   - Controller resolves toolbar `action` strings to functions
   - Controller creates window with `ns.Window(cfg)`

5. **Update Model.lua files** — remove window constants
   - Remove `Model.title`, `Model.windowWidth`, `Model.windowHeight`
   - These now live in the XML

6. **Files to modify:**
   - `lua/ui/xml.lua` — add Window/Toolbar/ToolbarItem tags, update render logic
   - `examples/hello/` — create Window.xml, simplify Controller/Model
   - `examples/list/` — same
   - `examples/layout/` — same
   - `examples/weather/` — same
   - `examples/live/` — same
   - `examples/mail/` — same
   - `examples/welcome/` — same
   - `examples/preview/` — no window, skip
   - `examples/IDEKit/` — skip (already uses Lua components, not XML)
   - `tests/examples.test.lua` — verify still passes

### Controller Pattern After Refactor

```lua
local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.mail.Model")

local VIEWS = "examples/mail/views/"

local ACTIONS = {
    compose = function(self) self:compose() end,
    refresh = function(self) self:refresh() end,
}

local Controller = {}
Controller.__index = Controller

function Controller.new()
    return setmetatable({ ... }, Controller)
end

function Controller:createWindow()
    local cfg, refs = xml.renderFile(VIEWS .. "Window.xml")

    -- Resolve toolbar actions
    for _, item in ipairs(cfg.toolbar or {}) do
        if item.action and ACTIONS[item.action] then
            local actionFn = ACTIONS[item.action]
            item.action = function() actionFn(self) end
        end
    end

    self.mailboxList = refs.mailboxList
    self.messageList = refs.messageList
    self.detailPane  = refs.detailPane
    -- ... wire up refs ...

    self.window = ns.Window(cfg)
    return self.window
end
```

### XML File Structure Per Example

Each example's `views/` directory gets a `Window.xml` that replaces the hardcoded
window config. The existing layout XML becomes the content inside `<Window>`.

Example: `examples/hello/views/Window.xml`
```xml
<Window title="Lua + ObjC Demo" width="480" height="420">
    <VStack flexGrow="1" padding="24" spacing="12" alignment="leading">
        <Label text="Hello from Lua" size="24" weight="bold" />
        ...
    </VStack>
</Window>
```

Example: `examples/mail/views/Window.xml`
```xml
<Window title="Mail" width="940" height="520" minWidth="640" minHeight="400">
    <Toolbar>
        <ToolbarItem id="compose" label="Compose"
                     icon="square.and.pencil" tooltip="New Message" />
    </Toolbar>
    <HSplit>
        <List ref="mailboxList" fixedWidth="180" ...>
            <Column id="name" title="Mailbox" />
        </List>
        ...
    </HSplit>
</Window>
```

### Backward Compatibility

- `xml.renderFile` for non-Window XML: unchanged `(view, refs)`
- `xml.renderFile` for Window XML: returns `(configTable, refs)`
- No changes to `ns.Window` itself — it already accepts the props table format
- IDEKit examples are unaffected (they use Lua components, not XML)
- Preview example is unaffected (no window)
