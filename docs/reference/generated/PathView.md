<!-- GENERATED from lua/embedded/AppKit.lua:1484 — do not edit by hand. -->

# PathView

Displays a filesystem path as a navigable or inspectable view.

```xml
<PathView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `fillColor` | color | optional | Component-specific setting passed to the native control. |
| `height` | number | optional | Component-specific setting passed to the native control. |
| `lineWidth` | number | optional | Stroke width in points. |
| `strokeColor` | color | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1484` (`AppKit.PathView`)_
