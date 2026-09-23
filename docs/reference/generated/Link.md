<!-- GENERATED from lua/embedded/AppKit.lua:1255 — do not edit by hand. -->

# Link

Opens or navigates to a destination when activated.

```xml
<Link ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `label` | value | optional | Component-specific setting passed to the native control. |
| `title` | value | optional | Component-specific setting passed to the native control. |
| `url` | string | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Link />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1255` (`AppKit.Link`)_
