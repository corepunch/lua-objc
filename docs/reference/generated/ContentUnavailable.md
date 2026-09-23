<!-- GENERATED from lua/embedded/AppKit.lua:1270 — do not edit by hand. -->

# ContentUnavailable

Presents a native empty, unavailable, or no-results state.

```xml
<ContentUnavailable ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `description` | value | optional | Secondary explanatory text for an unavailable state. |
| `imageSize` | number | optional | Symbol or image size in points. |
| `lines` | number | optional | Maximum number of visible text lines. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |
| `systemImage` | string | optional | Component-specific setting passed to the native control. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1270` (`AppKit.ContentUnavailable`)_
