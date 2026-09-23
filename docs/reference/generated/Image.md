<!-- GENERATED from lua/embedded/AppKit.lua:1005 — do not edit by hand. -->

# Image

Displays a raster or vector image asset.

```xml
<Image ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `contentMode` | string | optional | Image scaling mode such as fit or fill. |
| `fileIcon` | string | optional | Displays a system file icon for the path. |

## Example

```etlua
<Image />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:1005` (`AppKit.Image`)_
