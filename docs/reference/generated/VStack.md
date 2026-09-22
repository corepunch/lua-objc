<!-- GENERATED from lua/embedded/AppKit.lua:351 — do not edit by hand. -->

# VStack

A view that arranges its subviews in a vertical line.

```lua
ns.VStack { ... }
```

```xml
<VStack ... />
```

## Overview

Children in the array part stack top-to-bottom with 8pt sibling
spacing and no implicit outer padding. Set `padding` explicitly when
the group needs margins. Hidden children consume no space and add no
spacing.

## Topics

### Properties

| Name | Type | Required | Description |
|---|---|---|---|
| `spacing` | number | optional | Sibling spacing in points. |
| `padding` | number | optional | Explicit outer margins. |
| `alignment` | string | optional | Cross-axis alignment. |
| `fillWidth` | boolean | optional | Expand to the parent width. |
| `fillHeight` | boolean | optional | Expand to the parent height. |

## Example

```lua
ns.VStack { ns.Text "Line 1", ns.Text "Line 2" }
```

## Platform notes

- AppKit NSView (vertical layout). UIKit UIView (vertical layout).

## See Also

- `HStack`
- `ZStack`
- `FlowStack`
- `Spacer`

---

_Source: `lua/embedded/AppKit.lua:351` (`AppKit.VStack`)_
