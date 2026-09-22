<!-- GENERATED from lua/embedded/AppKit.lua:916 — do not edit by hand. -->

# Button

A push button backed by a native button control.

```lua
ns.Button { ... }
```

```xml
<Button ... />
```

## Overview

The optional `action` callback fires via target-action and receives
the sender as its first argument. Make the most likely safe action
primary; never make a destructive action primary. Prefer `Link` for
navigation and `Toggle` for on/off state.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `title` | string | required | Button label. Use a precise verb. |
| `action` | function | optional | Called with sender: `function(btn) ... end`. |
| `style` | string | optional | "plain", "link", "primary", or "row". |
| `systemImage` | string | optional | SF Symbol name shown beside the title. |
| `size` | number | optional | Title font size; omit for system default. |
| `weight` | string | optional | Title font weight. |
| `disabled` | boolean | optional | Disables the control when true. |
| `accessibilityLabel` | string | optional | VoiceOver label. |

## Example

```lua
ns.Button { title = "Save", action = function() save() end }
```

## Platform notes

- AppKit NSButton (rounded) or LuaActionButton (compound). UIKit UIButton.

## See Also

- `Link`
- `Toggle`
- `Toolbar`

---

_Source: `lua/embedded/AppKit.lua:916` (`AppKit.Button`)_
