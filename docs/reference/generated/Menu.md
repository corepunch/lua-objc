<!-- GENERATED from lua/embedded/UIKit.lua:850 — do not edit by hand. -->

# Menu

Presents a native menu of related commands.

```xml
<Menu ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `children` | table | optional | Component-specific setting passed to the native control. |
| `items` | table | optional | Component-specific setting passed to the native control. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Menu />
```

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:850` (`UIKit.Menu`)_
