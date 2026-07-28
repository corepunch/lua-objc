# Native AppKit surface

## Decision

AppKit properties come from Objective-C, not bridge metadata.

- `__index` reads with `valueForKey:`.
- `__newindex` writes with `setValue:forKey:`.
- Exported subclasses add semantic Lua names such as `text`.
- The `NSView` base extension owns framework layout properties.
- `Size`, `Point`, and `Rect` remain explicit value userdata.
- Specialized operations that are not properties remain native methods.

The AppKit/UIKit XML schemas and their generated bridge files are removed.
Each platform now owns ordinary native constructors, bindings, and KVC
accessors.

## Public naming

- `NSSize` → `ns.Size`
- `NSPoint` → `ns.Point`
- `NSRect` → `ns.Rect`
- No `NSSize`/`NSPoint`/`NSRect` compatibility exports
- Getter/setter pairs become assignments where they represent state

Examples:

```lua
label.text = "Hello"
field.editable = true
window.size = ns.Size(800, 600)
editor.wrapMode = true
```

## Native ownership

- `LuaTextField` exposes `text`, `placeholder`, and `lineLimit`.
- `LuaTextScrollView` exposes `text`, `language`, and `wrapMode`.
- `LuaNativeTextView` exposes `text`.
- `LuaWindow` is the exported window class.
- AppKit-native names such as `editable`, `hidden`, `toolTip`, and `rowHeight`
  require no declaration because KVC discovers them directly.

## Verification

- Headless tests cover property read/write round trips and unrelated-state
  preservation.
- Schema tests ensure both platform XML files are absent and native classes own
  semantic/layout properties.
- Build and test with `make test`.
