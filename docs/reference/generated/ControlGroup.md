<!-- GENERATED from lua/embedded/AppKit.lua:545 — do not edit by hand. -->

# ControlGroup

Groups related controls into a compact row.

```xml
<ControlGroup ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `alignment` | value | optional | Component-specific setting passed to the native control. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<ControlGroup />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:545` (`AppKit.ControlGroup`)_
