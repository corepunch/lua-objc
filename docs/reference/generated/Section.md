<!-- GENERATED from lua/embedded/AppKit.lua:484 — do not edit by hand. -->

# Section

Groups related content and may display a header.

```xml
<Section ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `header` | table | optional | Section or group heading. |

## Example

```etlua
<Section />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:484` (`AppKit.Section`)_
