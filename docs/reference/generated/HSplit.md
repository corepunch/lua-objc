<!-- GENERATED from lua/embedded/AppKit.lua:668 — do not edit by hand. -->

# HSplit

Places panes side by side in a native split view.

```xml
<HSplit ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `proportions` | table | optional | Initial split pane proportions; values are normalized by the split view. |

## Example

```etlua
<HSplit />
```

## Platform notes

- AppKit uses the AppKit implementation.

---

_Source: `lua/embedded/AppKit.lua:668` (`AppKit.HSplit`)_
