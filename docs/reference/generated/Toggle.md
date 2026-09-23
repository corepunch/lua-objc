<!-- GENERATED from lua/embedded/AppKit.lua:1305 — do not edit by hand. -->

# Toggle

Represents an on/off value with a native switch or checkbox.

```xml
<Toggle ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | function | optional | Component-specific setting passed to the native control. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `is_on` | value | optional | Current on/off value (legacy spelling). |
| `label` | value | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Toggle />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1305` (`AppKit.Toggle`)_
