<!-- GENERATED from lua/embedded/UIKit.lua:223 — do not edit by hand. -->

# NavigationLink

Navigates to a destination within a navigation stack.

```xml
<NavigationLink ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `destination` | string | optional | Navigation destination associated with the link. |
| `label` | value | optional | Component-specific setting passed to the native control. |
| `navigation` | string | optional | Navigation stack that receives the destination. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:223` (`UIKit.NavigationLink`)_
