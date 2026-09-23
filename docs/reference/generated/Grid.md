<!-- GENERATED from lua/embedded/AppKit.lua:723 — do not edit by hand. -->

# Grid

Aligns child views into rows and columns.

```xml
<Grid ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `alignment` | value | optional | Component-specific setting passed to the native control. |
| `content` | value | optional | Rendered child content or the control’s text value. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Grid />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:723` (`AppKit.Grid`)_
