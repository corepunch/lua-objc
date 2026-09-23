<!-- GENERATED from lua/embedded/AppKit.lua:495 — do not edit by hand. -->

# GroupBox

Groups related controls inside a titled native box.

```xml
<GroupBox ... />
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
<GroupBox />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:495` (`AppKit.GroupBox`)_
