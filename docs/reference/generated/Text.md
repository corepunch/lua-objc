<!-- GENERATED from lua/embedded/AppKit.lua:776 — do not edit by hand. -->

# Text

A view that displays one or more lines of read-only text.

```xml
<Text ... />
```

## Overview

Accepts a plain string or a table whose first element is the string.
Use `size` and `weight` for hierarchy; prefer system typography over
hard-coded custom fonts. Long text wraps under the parent width
proposal unless `lineLimit` truncates it.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `[1]` | string | required | Label content. |
| `size` | number | optional | System font size in points. |
| `weight` | string | optional | System font weight (e.g. "bold", "semibold"). |
| `color` | string | optional | Semantic system color name. |
| `alignment` | string | optional | One of "leading", "center", "trailing". |
| `lineLimit` | number | optional | Maximum lines; 0 means unlimited. |
| `truncation` | string | optional | One of "head", "middle", "tail". |
| `wrapping` | string | optional | "word" (default) or "character". |

## Example

```etlua
<Label>Hello</Label>
```

```etlua
<Label size="16" weight="bold">Hello</Label>
```

## Platform notes

- AppKit NSTextField (non-editable, bezel-less). UIKit UILabel.

## See Also

- [Title](Title.md)
- [Label](Label.md)
- [TextField](TextField.md)

---

_Source: `lua/embedded/AppKit.lua:776` (`AppKit.Text`)_
