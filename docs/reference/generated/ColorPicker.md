<!-- GENERATED from lua/embedded/AppKit.lua:1418 — do not edit by hand. -->

# ColorPicker

Selects a color using the platform color control.

```xml
<ColorPicker ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `color` | color | optional | Component-specific setting passed to the native control. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `onChange` | function | optional | Callback invoked when the value changes. |

## Example

```etlua
<ColorPicker />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1418` (`AppKit.ColorPicker`)_
