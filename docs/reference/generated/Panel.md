<!-- GENERATED from lua/embedded/AppKit.lua:257 — do not edit by hand. -->

# Panel

Creates a floating utility panel with native AppKit panel behavior.

```xml
<Panel ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `height` | number | optional | Component-specific setting passed to the native control. |
| `material` | string | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Panel title="Example" />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:257` (`AppKit.Panel`)_
