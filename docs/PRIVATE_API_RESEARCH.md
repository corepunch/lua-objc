# Private navigation palettes and LazyLayout

**Status:** Research only; no private selectors are called by lua-objc.
**Default:** Disabled. No experimental runtime switch is shipped.
**Reviewed:** 2026-09-23.

## Findings and limits

Community reports describe navigation-bar top and bottom palettes and an
internal lazy-layout protocol. The referenced examples are not Apple API
documentation. The exact class/selector signatures, supported OS versions, and
behavior across releases have not been verified against an SDK or device in
this repository. This document therefore records no confirmed availability
range and includes no selector implementation.

The previous draft listed guessed `_setTopPalette:` / `_setBottomPalette:`
selectors and claimed an iOS 17–26 support range. Those claims were not
substantiated and have been removed. Treat `_UINavigationBarPalette`,
`_topPalette`, `_bottomPalette`, and `LazyLayout` as unverified names from
community research, not callable APIs.

## Public path

Use `UINavigationItem` and `UINavigationController` for navigation-bar
content, search, and toolbar items. Apple documents
[`UINavigationItem.searchController`](https://developer.apple.com/documentation/uikit/uinavigationitem/searchcontroller)
and its navigation interface guidance. Use native `List` for virtualized
collections; lua-objc maps it to public AppKit/UIKit table controls. These are
the supported paths in app code.

## Opt-in policy

`enablePrivateNavigationPalettes` and `enablePrivateLazyLayout` are documented
as **false by default**. They are planning flags only; there is no runtime
implementation to enable in this revision. Do not add app examples or test
fixtures that invoke private selectors. A future experiment must be isolated in
one Objective-C source file, gated before every invocation, version-checked,
covered by a public fallback, and kept out of the default app/test path.

Private APIs are unsupported and may change or disappear in any OS release.
Using them can cause App Review rejection or removal after an OS update. A
future opt-in implementation must surface this risk before enabling the code.

## LazyLayout

No private protocol implementation or version claim is included. Keep using
`List` until a public layout API or a separately authorized, device-verified
experiment demonstrates a need that public collections cannot meet.
