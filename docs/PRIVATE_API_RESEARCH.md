# Private navigation palettes and LazyLayout

**Status:** Experimental opt-in navigation palettes; `LazyLayout` remains research only.
**Reviewed:** 2026-09-23.

## Selector spike

The [community sample](https://github.com/AlexChekel1337/navigation-bar-palette)
uses `_UINavigationBarPalette`, `initWithContentView:`, and
`UINavigationItem._setBottomPalette:`. Reverse-engineered runtime headers also
list `_setTopPalette:`. These names are not Apple API contracts. The bridge
checks for the class and selectors at runtime before calling them.

The private path is gated to iOS 26.5, the only simulator runtime available for
this spike. Both palettes appeared in an iPhone 17 simulator screenshot; the
public fallback was also viewed with the flag off. No behavior or support
range is claimed for other iOS versions or physical devices.
`LazyLayout` has no verified selector or protocol signature, so no runtime
implementation is included.

## Public fallback and opt-in

`<NavigationStack>` accepts nested `<TopPalette>` and `<BottomPalette>` views.
By default, public `UINavigationItem.titleView` hosts the top content and a
public `UIToolbar` hosts the bottom content. Set
`enablePrivateNavigationPalettes="true"` to try the private palette. A missing
class, selector, or supported runtime automatically uses the public placement.
All private runtime calls live in `src/uikit/private_navigation_palettes.m`.

```xml
<NavigationStack title="Discover" enablePrivateNavigationPalettes="true">
  <VStack><Label text="Discover" /></VStack>
  <BottomPalette><HStack><Label text="For You" /></HStack></BottomPalette>
</NavigationStack>
```

The opt-in example is `demo/private-palettes/`; it is excluded from the
default example list. Public `UINavigationItem` and `UINavigationController`
APIs remain the supported production path. For large collections use native
`List`, not private `LazyLayout`.

## Risk

Private APIs are unsupported and can change or disappear in any OS release.
Using them can cause App Review rejection or removal after an update. The
presence check does not guarantee layout, accessibility, or future behavior.
Do not enable this option in an App Store app unless you accept that risk.
