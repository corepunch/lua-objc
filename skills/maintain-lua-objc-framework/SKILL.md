---
name: maintain-lua-objc-framework
description: Maintain and extend lua-objc native framework code in Objective-C `.m` files. Use when changing AppKit or UIKit bridge primitives, native controls, userdata/KVC behavior, layout, tables or outlines, callbacks, async Lua state ownership, HTTP/JSON services, module registration, source organization, native build rules, or headless framework tests.
---

# Maintain the lua-objc Framework

Keep application behavior in Lua. Change native code only for framework
infrastructure, platform integration, or a real AppKit/UIKit-backed leaf
control.

## Locate the subsystem

Read `src/README.md`, then search for the exact bridge symbol:

```sh
rg -n 'bridge_name|NativeClass|publicLuaName' src lua tests
```

Open only the matching fragment:

- `src/main.m` — AppKit constants, registration, host entry point
- `src/appkit/` — AppKit implementation fragments
- `src/uikit/bridge.m` — UIKit constants and registration
- `src/uikit/` — UIKit implementation fragments
- `src/shared/` — platform-neutral Lua errors, state ownership, timers,
  HTTP, and JSON
- `lua/embedded/AppKit.lua` / `UIKit.lua` — public declarative wrappers
- `lua/ui/xml.lua` — cross-platform etlua/XML template engine and tag registry

Do not compile fragments independently. Each platform root includes its
fragments into one translation unit so static keys, Lua state, and callback
types remain shared. The Makefile discovers fragment dependencies with `find`.

## Choose Lua wrapper or native bridge

Try the generic native surface before adding C:

- `bridge._create("NativeClass")` for controls with a usable default
  initializer;
- userdata property access for KVC-compatible values;
- `bridge._perform(view, "selectorName", optionalArgument)` for ordinary
  selectors;
- `bridge._callback(view, fn)` for target/action controls;
- `applyLayout(view, props)` for standard layout modifiers.

For example, a basic AppKit `SearchField` should first be attempted entirely in
`lua/embedded/AppKit.lua` with `_create("NSSearchField")`, KVC properties,
`_callback`, and `sizeToFit`. Add a dedicated `bridge_search_field` only if a
required initializer, delegate protocol, event contract, ownership rule, or
non-KVC value cannot be represented correctly by the generic bridge.

## Implement a bridge change

1. Prove the generic path is insufficient before adding a native bridge
   function. Record the missing native capability in a concise code comment.
2. Put platform-neutral behavior in `src/shared/`; keep AppKit/UIKit types in
   their platform folder.
3. Add visual/layout constants to the platform root, never inline magic
   geometry.
4. Create a real native control and expose it as bridge-compatible userdata.
   Balance `CFBridgingRetain` with the userdata `__gc` release path.
5. Store per-object state with associated objects when possible. Avoid new
   global maps.
6. Keep Lua registry refs tied to the correct state. Resolve coroutine owners
   with `owner_for_state`; never restore raw `lua_State*` lookup tables or the
   deleted `bridge_main` workaround.
7. Register the native function in the platform root's `bridge_lib`.
8. Add or update the public wrapper in the corresponding embedded Lua module.
   Preserve established public names unless performing an intentional
   migration.
9. Add regression coverage before declaring the change complete.
10. **If the change introduces a new view type used in etlua templates:** add
    a handler to `xml.registry` in `lua/ui/xml.lua` so the template system can
    instantiate it from XML tags.

When a feature requires state-dependent structural reevaluation, stop adding
feature-specific native subtree mutation. Revisit the retained-description and
reconciliation boundary documented in `docs/PROJECT_REFERENCE.md`.

## XML template engine (`lua/ui/xml.lua`)

### Adding a new XML tag

Tags are handler functions in `xml.registry`:

```lua
xml.registry["MyWidget"] = function(ns, attrs, children)
    local props = layoutProps(attrs)  -- auto-coerces padding, spacing, etc.
    props.title = attrs.title or ""
    for _, c in ipairs(children) do props[#props + 1] = c end
    return ns.MyWidget(props)
end
```

- `ns` — the platform module (AppKit or UIKit)
- `attrs` — string table from XML attribute parsing
- `children` — already-compiled child views
- Return a native view userdata (or a plain table for passthrough tags like `<ToolbarItem>`)

Helper functions: `layoutProps(attrs)` applies common layout keys; `num(v)`,
`bool(v)`, `coerce(v)` handle type conversion.

### Passing pre-built userdata through templates

Some views (charts, canvases) are constructed imperatively in the Controller
and must be embedded in declarative etlua templates. Use the `renderData`
upvalue + a passthrough tag:

```lua
-- In xml.lua: declare renderData before makeRegistry()
local renderData = nil

-- Tag handler references renderData upvalue
R["Chart"] = function(ns, a, _)
    local key = a.data or "chart"
    if renderData[key] then return renderData[key] end
    error("xml: <Chart> requires pre-built chart")
end

-- In render(), set before compilation and clear after
renderData = data
local views = compile(nodes, ns, registry, refs)
renderData = nil
```

The `local renderData` declaration must precede `makeRegistry()` so closures
capture it as an upvalue (not a global).

### etlua iteration patterns

etlua's `<% for %>` loops generate repeated XML elements before parsing.
Pre-compute iterable data structures in the Controller, not in templates:

```xml
<!-- Correct: data is pre-structured -->
<% for _, column in ipairs(stock.metricColumns) do %>
<VStack>
    <% for _, row in ipairs(column) do %>
    <Label text="<%= row[1] %>" />
    <% end %>
</VStack>
<% end %>
```

Do not call Lua constructors (`ns.Curve`, `ns.Text`, etc.) inside `<% %>` blocks.
They execute before XML parsing and produce unparseable output. Keep template
logic limited to iteration, conditionals, and value injection.

## Layout dump verification

The `--dump-layout` flag produces an XML file of the complete native view
hierarchy with computed frames, intrinsic sizes, text content, and explicit
clipping/overflow flags. Use it as the primary visual verification tool:

```sh
./lua-objc --dump-layout=/tmp/layout.xml examples/stocks/init.lua

# Check for problems
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml

# Verify specific content
rg -n 'text="Open"|text="52W H"' /tmp/layout.xml

# Verify at different window sizes
./lua-objc --dump-layout=/tmp/layout-small.xml --width=760 --height=468 \
  examples/stocks/init.lua
```

The dump XML records per-node: class, frame, intrinsic/fitting sizes,
clip-to-bounds, overflow state, and text content. Table nodes additionally
record column widths and per-cell text geometry with `cropped` and `ellipsis`
flags. Always inspect the dump before and after layout changes so diagnosis
and fix are both evidenced.

## Verify

Read [references/testing.md](references/testing.md) whenever native behavior,
module registration, examples, or test infrastructure changes.

At minimum:

```sh
make test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make uikit
git diff --check
```

Use `xcode-select -p` and `xcrun --sdk iphonesimulator --show-sdk-path` before
assuming the UIKit SDK is unavailable. Setting `DEVELOPER_DIR` for one command
does not change system configuration.

Headless tests prove construction, properties, layout contracts, and data
mutation without showing windows. They do not replace required screenshot,
resize, state, accessibility, light, and dark visual QA for UI changes.
