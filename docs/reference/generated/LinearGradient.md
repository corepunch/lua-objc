<!-- GENERATED from lua/embedded/UIKit.lua:746 — do not edit by hand. -->

# LinearGradient

Fills content with a linear color gradient.

```xml
<LinearGradient ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `bottomAlpha` | number | optional | Opacity of the gradient at the bottom edge. |
| `middleAlpha` | number | optional | Component-specific setting passed to the native control. |
| `middleLocation` | number | optional | Position of the middle gradient stop, from 0 to 1. |
| `topAlpha` | number | optional | Opacity of the gradient at the top edge. |

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:746` (`UIKit.LinearGradient`)_
