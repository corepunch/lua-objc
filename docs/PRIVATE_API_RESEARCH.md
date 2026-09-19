# Private API Research: Navigation Bar Palettes & LazyLayout

**Status:** Research spike (opt-in only)  
**Risk Level:** HIGH — App Store rejection possible  
**Default:** DISABLED

This document explores two private Apple APIs that offer system-quality UX but carry App Store risk.

## Overview

Private APIs discovered in iOS 26+ / macOS 26+ that system apps use:

1. **`_UINavigationBarPalette`** — Bottom/top palette for nav bar customization
2. **`LazyLayout`** — System's virtualization protocol used internally

Both are undocumented, unsupported, and subject to removal or breaking changes.

## 1. Navigation Bar Palettes

### What It Provides

Custom views pinned to the navigation bar with correct layout, a11y, large titles, and Liquid Glass.

References:
- Jacob Bartlett: https://x.com/jacobtechtavern/status/2100878754482376971
- Seb Vidal original: https://x.com/SebJVidal/status/1748659522455937213
- iOS 18 top palette: https://x.com/SebJVidal/status/1893218526690746819
- Example: https://github.com/AlexChekel1337/navigation-bar-palette

### Private API Shape (Research)

```objc
// Pseudocode from reverse engineering
@interface UINavigationBar (Private)
- (void)_setBottomPalette:(UIView *)palette;
- (void)_setTopPalette:(UIView *)palette;
@property(nonatomic) BOOL _prefersLargeTitle;
@end
```

### Public Fallback (Recommended)

Use `UINavigationItem` APIs first:

```swift
navigationItem.rightBarButtonItems = [...]  // Public
navigationItem.searchController = ...        // Public
navigationItem.backButtonDisplayMode = ...   // Public
```

Only use private palettes if public APIs cannot achieve the UX.

### Lua Shape (If Enabled)

```lua
if enable_private_navigation_palettes then
    nav:setBottomPalette(tabSelector)
end
```

## 2. Private LazyLayout

### What It Provides

The protocol Apple uses internally for virtualization in Lists, Grids, etc.

Reference: https://x.com/vistar941/status/2100945557787435095

### Why It Matters

Developers have been asking for public access. The protocol is already the foundation of SwiftUI's `LazyVStack`, `LazyVGrid`, etc.

### Public Alternative (Recommended)

Use public `UITableView` / `NSTableView` / `UICollectionView`:

```lua
-- Already implemented in lua-objc
local list = ns.List(items)  -- Public API, virtualized
```

Only research private LazyLayout if public collection views don't meet performance needs.

## Implementation Constraints (Non-Negotiable)

1. **Isolation in one ObjC file**
   - All `NSClassFromString()` / selector calls in one place
   - Easy to remove if APIs change or App Store rejects

2. **Version gating**
   - Detect iOS/macOS version
   - Fall back to public APIs on older OS versions
   - No crash if private API unavailable

3. **Opt-in flag**
   ```lua
   -- config.lua or settings
   ENABLE_PRIVATE_NAVIGATION_PALETTES = false  -- Default: safe
   ENABLE_PRIVATE_LAZYLAYOUT = false           -- Default: safe
   ```

4. **Risk warning in skill**
   - If flag is on, skill warns agents:
     > ⚠️ Using private APIs. Your app may be rejected from the App Store.
   - Link to this document

5. **No private API in default tests**
   - `make test` uses only public APIs
   - `make test-experimental` runs with private APIs enabled

6. **Product rule alignment**
   - `AGENTS.md` says: "if public API can do it, don't use private"
   - Same rule applies here

## Feasibility Assessment

### Navigation Palettes
- ✅ Stable across iOS 17–26 (observed)
- ⚠️ Undocumented changes between point releases possible
- ❌ No guarantee in iOS 27+

### LazyLayout
- ⚠️ Internal protocol, minimal public documentation
- ❌ High risk of breaking changes
- ✅ Alternative (UITableView/UICollectionView) is public and performant

## Recommendation

**For lua-objc v1.0:**

1. **Skip navigation palettes** — Use public `UINavigationItem` APIs
2. **Skip LazyLayout research** — Public `List` / `UICollectionView` is sufficient

**Future (v2.0+):**

- **Navigation palettes** — Low-risk spike if user demand is high
- **LazyLayout** — High-risk spike; public virtualization usually sufficient

## Spiking Code Template

If pursuing private APIs later:

```objc
// Private API isolation file: src/uikit/private_apis.m

#pragma mark - Private API Helpers (Experimental)

static BOOL canUseNavigationPaletteAPI(void) {
    // Check iOS version, selector availability
    return NSClassFromString(@"UINavigationBar") != nil &&
           [UINavigationBar instancesRespondToSelector:
               NSSelectorFromString(@"_setBottomPalette:")];
}

- (void)setBottomPaletteIfAvailable:(UIView *)view {
    if (!canUseNavigationPaletteAPI()) return;
    
    SEL selector = NSSelectorFromString(@"_setBottomPalette:");
    if ([self respondsToSelector:selector]) {
        [self performSelector:selector withObject:view];
    }
}
```

## App Store Guidance

From past rejections & discussions:

> "Apps that use private APIs will be rejected. This includes using
> undocumented selectors or accessing private frameworks."

However:
- Private APIs in system apps are allowed for Apple's own use
- Rejection is not automatic; depends on whether private API is visible to users
- Some private APIs have been used in shipping apps without rejection (rare)

**Safest path:** Use only public APIs. Private APIs are for research only.

## Summary

| Aspect | Palettes | LazyLayout |
|--------|----------|-----------|
| **Complexity** | Medium | High |
| **Risk** | Medium | High |
| **Public alternative** | Yes (good) | Yes (sufficient) |
| **v1.0 priority** | Low | Skip |
| **Recommendation** | Skip for now | Skip for now |

Use private APIs only if:
1. Product team explicitly requests it
2. Public alternative is demonstrably insufficient
3. Team commits to maintenance burden
4. Users are warned of rejection risk

Otherwise, stick with public APIs and win on performance with better data structures and algorithms.
