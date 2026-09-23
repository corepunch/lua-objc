<!-- GENERATED from lua/embedded/AppKit.lua:615 — do not edit by hand. -->

# OutlineGroup

Builds a nested disclosure hierarchy from tree data.

```xml
<OutlineGroup ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `alignment` | value | optional | Component-specific setting passed to the native control. |
| `data` | table | optional | Input rows or values consumed by the component. |
| `expanded` | boolean | optional | Component-specific setting passed to the native control. |
| `items` | table | optional | Component-specific setting passed to the native control. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<OutlineGroup />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:615` (`AppKit.OutlineGroup`)_
