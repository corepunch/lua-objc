<!-- GENERATED from lua/embedded/AppKit.lua:1402 — do not edit by hand. -->

# DatePicker

Selects a date or time value.

```xml
<DatePicker ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `onChange` | function | optional | Callback invoked when the value changes. |
| `time` | value | optional | Whether the date picker includes time selection. |
| `timestamp` | number | optional | Date value represented as a Unix timestamp. |

## Example

```etlua
<DatePicker />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1402` (`AppKit.DatePicker`)_
