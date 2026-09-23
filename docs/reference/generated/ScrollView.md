<!-- GENERATED from lua/embedded/AppKit.lua:635 — do not edit by hand. -->

# ScrollView

Adds native scrolling around one content view.

```xml
<ScrollView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `content` | value | optional | Rendered child content or the control’s text value. |
| `contentHeight` | number | optional | Scroll content height; zero lets the content size itself. |
| `contentWidth` | number | optional | Scroll content width; zero lets the content size itself. |
| `horizontal` | boolean | optional | Component-specific setting passed to the native control. |
| `vertical` | boolean | optional | Component-specific setting passed to the native control. |

## Example

```etlua
<ScrollView />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:635` (`AppKit.ScrollView`)_
