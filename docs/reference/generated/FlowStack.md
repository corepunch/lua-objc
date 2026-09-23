<!-- GENERATED from lua/embedded/AppKit.lua:456 — do not edit by hand. -->

# FlowStack

Wraps child views into additional rows or columns as space runs out.

```xml
<FlowStack ... />
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
<FlowStack />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:456` (`AppKit.FlowStack`)_
