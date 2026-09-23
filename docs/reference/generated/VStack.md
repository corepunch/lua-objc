<!-- GENERATED from lua/embedded/AppKit.lua:418 — do not edit by hand. -->

# VStack

A view that arranges its subviews in a vertical line.

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

```etlua
<VStack><Label>Line 1</Label><Label>Line 2</Label></VStack>
```

## Platform notes

- AppKit NSView (vertical layout). UIKit UIView (vertical layout).

## See Also

- [HStack](HStack.md)
- [ZStack](ZStack.md)
- [FlowStack](FlowStack.md)
- [Spacer](Spacer.md)

---

_Source: `lua/embedded/AppKit.lua:418` (`AppKit.VStack`)_
