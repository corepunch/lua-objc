<!-- GENERATED from lua/embedded/UIKit.lua:897 — do not edit by hand. -->

# MaterialView

Displays content using a native visual material.

```xml
<MaterialView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `content` | value | optional | Rendered child content or the control’s text value. |
| `material` | string | optional | Component-specific setting passed to the native control. |

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:897` (`UIKit.MaterialView`)_
