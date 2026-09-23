<!-- GENERATED from lua/embedded/AppKit.lua:1512 — do not edit by hand. -->

# Curve

Renders a data-driven curve in a native drawing surface.

```xml
<Curve ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `chartPadding` | number | optional | Inset around the plotted data, in points. |
| `data` | table | optional | Input rows or values consumed by the component. |
| `fallbackMessage` | string | optional | Message shown when no chart data can be rendered. |
| `fillArea` | boolean | optional | Fills the area under the plotted curve. |
| `fillColor` | color | optional | Component-specific setting passed to the native control. |
| `fillWidth` | boolean | optional | Component-specific setting passed to the native control. |
| `fixedHeight` | value | optional | Component-specific setting passed to the native control. |
| `height` | number | optional | Component-specific setting passed to the native control. |
| `lineWidth` | number | optional | Stroke width in points. |
| `strokeColor` | color | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1512` (`AppKit.Curve`)_
