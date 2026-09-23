<!-- GENERATED from lua/embedded/AppKit.lua:358 — do not edit by hand. -->

# Preview

Creates a fixed-size preview root for the IDE canvas.

```xml
<Preview ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `content` | value | optional | Rendered child content or the control’s text value. |
| `height` | number | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Preview />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:358` (`AppKit.Preview`)_
