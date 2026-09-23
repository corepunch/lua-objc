<!-- GENERATED from lua/embedded/AppKit.lua:1446 — do not edit by hand. -->

# Divider

Draws a horizontal or vertical native divider.

```xml
<Divider ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `orientation` | string | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Divider />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1446` (`AppKit.Divider`)_
