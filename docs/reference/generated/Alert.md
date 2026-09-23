<!-- GENERATED from lua/embedded/AppKit.lua:1754 — do not edit by hand. -->

# Alert

Presents a native alert and returns the selected response.

```xml
<Alert ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `buttons` | table | optional | Alert button titles, in display order. |
| `message` | string | optional | Explanatory message shown in an alert. |
| `title` | value | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Alert title="Example" />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1754` (`AppKit.Alert`)_
