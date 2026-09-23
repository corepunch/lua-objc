<!-- GENERATED from lua/embedded/AppKit.lua:1057 — do not edit by hand. -->

# List

Displays rows of data in a native table or list control.

```xml
<List ... />
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
| `onActivate` | function | optional | Callback invoked when a row or item is activated. |
| `onSelect` | function | optional | Callback invoked when row selection changes. |
| `refresh` | function | optional | Callback invoked to refresh the displayed data. |
| `rowHeight` | number | optional | Requested table row height, in points. |
| `style` | string | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<List />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1057` (`AppKit.List`)_
