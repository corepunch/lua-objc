<!-- GENERATED from lua/embedded/AppKit.lua:1382 — do not edit by hand. -->

# Picker

Selects one value from a set of options.

```xml
<Picker ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | function | optional | Component-specific setting passed to the native control. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `options` | table | optional | Selectable options or menu entries. |
| `value` | table | optional | Current selected, edited, or measured value. |

## Example

```etlua
<Picker />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1382` (`AppKit.Picker`)_
