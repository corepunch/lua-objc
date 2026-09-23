<!-- GENERATED from lua/embedded/AppKit.lua:1328 — do not edit by hand. -->

# Slider

Selects a numeric value within a continuous range.

```xml
<Slider ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | function | optional | Component-specific setting passed to the native control. |
| `allowsTickMarkValuesOnly` | boolean | optional | Restricts slider values to tick marks when true. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `max` | number | optional | Component-specific setting passed to the native control. |
| `min` | number | optional | Component-specific setting passed to the native control. |
| `tickMarks` | table | optional | Slider tick mark positions. |
| `value` | table | optional | Current selected, edited, or measured value. |

## Example

```etlua
<Slider />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1328` (`AppKit.Slider`)_
