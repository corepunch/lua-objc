<!-- GENERATED from lua/embedded/AppKit.lua:1355 — do not edit by hand. -->

# Stepper

Increments or decrements a numeric value.

```xml
<Stepper ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | function | optional | Component-specific setting passed to the native control. |
| `autorepeat` | boolean | optional | Repeats stepper actions while the user holds a step button. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `increment` | number | optional | Component-specific setting passed to the native control. |
| `max` | number | optional | Component-specific setting passed to the native control. |
| `min` | number | optional | Component-specific setting passed to the native control. |
| `value` | table | optional | Current selected, edited, or measured value. |
| `wraps` | boolean | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Stepper />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1355` (`AppKit.Stepper`)_
