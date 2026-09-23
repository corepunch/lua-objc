<!-- GENERATED from lua/embedded/AppKit.lua:332 — do not edit by hand. -->

# MenuItem

Creates a native menu command with a keyboard equivalent and action.

```xml
<MenuItem ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | function | optional | Component-specific setting passed to the native control. |
| `keyEquivalent` | value | optional | Keyboard equivalent for the menu command. |
| `menu` | string | optional | Menu name that owns this item. |
| `modifiers` | table | optional | Keyboard modifiers required with the key equivalent. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:332` (`AppKit.MenuItem`)_
