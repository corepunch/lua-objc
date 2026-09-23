<!-- GENERATED from lua/embedded/UIKit.lua:733 — do not edit by hand. -->

# PageControl

Indicates pages and allows selecting the current page.

```xml
<PageControl ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `currentPage` | number | optional | Zero-based index of the currently visible page. |
| `numberOfPages` | number | optional | Component-specific setting passed to the native control. |
| `pages` | table | optional | Page data used to construct the page control. |

## Platform notes

- UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/UIKit.lua:733` (`UIKit.PageControl`)_
