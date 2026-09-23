<!-- GENERATED from lua/embedded/AppKit.lua:559 — do not edit by hand. -->

# DisclosureGroup

Shows a header that expands or collapses its child content.

```xml
<DisclosureGroup ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `alignment` | value | optional | Component-specific setting passed to the native control. |
| `expanded` | boolean | optional | Component-specific setting passed to the native control. |
| `header` | table | optional | Section or group heading. |
| `label` | value | optional | Component-specific setting passed to the native control. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<DisclosureGroup />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:559` (`AppKit.DisclosureGroup`)_
