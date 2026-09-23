<!-- GENERATED from lua/embedded/AppKit.lua:955 — do not edit by hand. -->

# TextEditor

Edits multiline text.

```xml
<TextEditor ... />
```

## Overview

This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `drawsBackground` | boolean | optional | Draws the control’s background when true. |
| `editable` | boolean | optional | Allows text editing when true. |
| `language` | string | optional | Component-specific setting passed to the native control. |
| `selectable` | boolean | optional | Allows text or rows to be selected when true. |
| `size` | number | optional | Component-specific setting passed to the native control. |
| `text` | string | optional | Initial or displayed text value. |
| `weight` | value | optional | Component-specific setting passed to the native control. |
| `wrapMode` | string | optional | Text wrapping mode. |

## Example

```etlua
<TextEditor />
```

## Platform notes

- AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.

---

_Source: `lua/embedded/AppKit.lua:955` (`AppKit.TextEditor`)_
