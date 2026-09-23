<!-- GENERATED from lua/embedded/AppKit.lua:1691 — do not edit by hand. -->

# NavigationStack

Manages a stack of screens and navigation transitions.

```xml
<NavigationStack ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `content` | value | optional | Rendered child content or the control’s text value. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1691` (`AppKit.NavigationStack`)_
