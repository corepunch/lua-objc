<!-- GENERATED from lua/embedded/AppKit.lua:1466 — do not edit by hand. -->

# ProgressView

Shows determinate or indeterminate progress.

```xml
<ProgressView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `indeterminate` | boolean | optional | Component-specific setting passed to the native control. |
| `value` | table | optional | Current selected, edited, or measured value. |

## Example

```etlua
<ProgressView />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1466` (`AppKit.ProgressView`)_
