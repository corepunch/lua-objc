<!-- GENERATED from lua/embedded/UIKit.lua:590 — do not edit by hand. -->

# Label

Combines an icon and title in a standard platform label.

```xml
<Label ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `accessibilityLabel` | value | optional | Component-specific setting passed to the native control. |
| `alignment` | value | optional | Component-specific setting passed to the native control. |
| `color` | color | optional | Component-specific setting passed to the native control. |
| `iconSize` | number | optional | Component-specific setting passed to the native control. |
| `iconWeight` | value | optional | System symbol weight for the label icon. |
| `italic` | boolean | optional | Component-specific setting passed to the native control. |
| `lineLimit` | number | optional | Maximum number of visible text lines. |
| `lines` | number | optional | Maximum number of visible text lines. |
| `size` | number | optional | Component-specific setting passed to the native control. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |
| `systemImage` | string | optional | Component-specific setting passed to the native control. |
| `truncation` | string | optional | Text truncation position: `head`, `middle`, or `tail`. |
| `weight` | value | optional | Component-specific setting passed to the native control. |
| `wrapping` | boolean | optional | Component-specific setting passed to the native control. |

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:590` (`UIKit.Label`)_
