<!-- GENERATED from lua/embedded/AppKit.lua:873 — do not edit by hand. -->

# TextField

Edits a single line of text.

```xml
<TextField ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `accessibilityLabel` | value | optional | Component-specific setting passed to the native control. |
| `bezeled` | boolean | optional | Shows the native bezel when true. |
| `bordered` | boolean | optional | Shows the native border when true. |
| `disabled` | boolean | optional | Component-specific setting passed to the native control. |
| `drawsBackground` | boolean | optional | Draws the control’s background when true. |
| `editable` | boolean | optional | Allows text editing when true. |
| `focusRing` | boolean | optional | Shows the native keyboard focus ring when true. |
| `onChange` | function | optional | Callback invoked when the value changes. |
| `onCommand` | function | optional | Callback invoked for the corresponding keyboard command. |
| `placeholder` | string | optional | Component-specific setting passed to the native control. |
| `secure` | boolean | optional | Masks entered text when true. |
| `selectable` | boolean | optional | Allows text or rows to be selected when true. |
| `size` | number | optional | Component-specific setting passed to the native control. |
| `value` | table | optional | Current selected, edited, or measured value. |
| `weight` | value | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<TextField />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:873` (`AppKit.TextField`)_
