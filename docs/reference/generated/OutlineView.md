<!-- GENERATED from lua/embedded/AppKit.lua:1130 — do not edit by hand. -->

# OutlineView

Displays hierarchical rows in a native outline control.

```xml
<OutlineView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `alternatingRows` | boolean | optional | Alternates row backgrounds when supported by the selected list style. |
| `bordered` | boolean | optional | Shows the native border when true. |
| `columns` | table | optional | Column descriptors defining the table structure. |
| `data` | table | optional | Input rows or values consumed by the component. |
| `drawsBackground` | boolean | optional | Draws the control’s background when true. |
| `gridLines` | value | optional | Grid line configuration for the table. |
| `header` | table | optional | Section or group heading. |
| `height` | number | optional | Component-specific setting passed to the native control. |
| `indentation` | number | optional | Indentation per outline depth, in points. |
| `onActivate` | function | optional | Callback invoked when a row or item is activated. |
| `onSelect` | function | optional | Callback invoked when row selection changes. |
| `rowHeight` | number | optional | Requested table row height, in points. |
| `style` | string | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<OutlineView />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1130` (`AppKit.OutlineView`)_
