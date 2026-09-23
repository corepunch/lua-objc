<!-- GENERATED from lua/embedded/AppKit.lua:927 — do not edit by hand. -->

# SearchField

Provides native search input and search-specific behavior.

```xml
<SearchField ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `accessibilityLabel` | value | optional | Component-specific setting passed to the native control. |
| `controlSize` | string | optional | Component-specific setting passed to the native control. |
| `onChange` | function | optional | Callback invoked when the value changes. |
| `onCommand` | function | optional | Callback invoked for the corresponding keyboard command. |
| `placeholder` | string | optional | Component-specific setting passed to the native control. |
| `value` | table | optional | Current selected, edited, or measured value. |

## Example

```etlua
<SearchField />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:927` (`AppKit.SearchField`)_
