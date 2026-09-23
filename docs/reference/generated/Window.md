<!-- GENERATED from lua/embedded/AppKit.lua:106 — do not edit by hand. -->

# Window

Creates the app window and hosts the rendered root view.

```xml
<Window ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `appearance` | string | optional | Window appearance: `system`, `light`, or `dark`. |
| `content` | value | optional | Rendered child content or the control’s text value. |
| `contentAccessory` | table | optional | Accessory view attached to the window content area. |
| `detail` | table | optional | Rendered detail pane view. |
| `detailWidth` | number | optional | Requested width of the detail pane, in points. |
| `height` | number | optional | Component-specific setting passed to the native control. |
| `hideTitle` | boolean | optional | Component-specific setting passed to the native control. |
| `minHeight` | number | optional | Component-specific setting passed to the native control. |
| `minWidth` | number | optional | Component-specific setting passed to the native control. |
| `sidebar` | table | optional | Rendered navigation sidebar view. |
| `sidebarWidth` | number | optional | Component-specific setting passed to the native control. |
| `size` | number | optional | Component-specific setting passed to the native control. |
| `tabbingIdentifier` | string | optional | Identifier used to group tabbing windows. |
| `tabbingMode` | string | optional | Window tabbing mode. |
| `title` | value | optional | Component-specific setting passed to the native control. |
| `toolbar` | table | optional | Toolbar item descriptors. |
| `toolbarContentDividerAfter` | value | optional | Toolbar item identifier after which the content divider appears. |
| `toolbarLabels` | boolean | optional | Component-specific setting passed to the native control. |
| `transparentTitlebar` | boolean | optional | Uses a transparent title bar when true. |
| `visible` | boolean | optional | Component-specific setting passed to the native control. |
| `width` | number | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<Window title="Example" />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:106` (`AppKit.Window`)_
