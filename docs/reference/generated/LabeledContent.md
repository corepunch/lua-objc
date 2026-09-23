<!-- GENERATED from lua/embedded/AppKit.lua:527 — do not edit by hand. -->

# LabeledContent

Pairs a descriptive label with its value or child controls.

```xml
<LabeledContent ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `label` | value | optional | Component-specific setting passed to the native control. |
| `labelWeight` | value | optional | System font weight for the label. |
| `spacing` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<LabeledContent />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:527` (`AppKit.LabeledContent`)_
