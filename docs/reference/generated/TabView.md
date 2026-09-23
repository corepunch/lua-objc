<!-- GENERATED from lua/embedded/AppKit.lua:387 — do not edit by hand. -->

# TabView

Presents mutually exclusive content in native tabs.

```xml
<TabView ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `onChange` | function | optional | Callback invoked when the value changes. |
| `selected` | table | optional | Selected option, tab, or row identifier. |
| `style` | string | optional | Component-specific setting passed to the native control. |
| `tabs` | table | optional | Tab definitions containing a title and content. |

## Example

```etlua
<TabView />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:387` (`AppKit.TabView`)_
