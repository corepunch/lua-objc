<!-- GENERATED from lua/embedded/AppKit.lua:281 — do not edit by hand. -->

# Sheet

Creates a sheet window for presentation from a parent window.

```xml
<Sheet ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `height` | number | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Sheet title="Example" />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:281` (`AppKit.Sheet`)_
