---
layout: default
title: Delight vs coverage
---

# Delight vs coverage

AdventureArena defines the iOS primitive set in [`ios.md`](ios.md).
Coverage is still the contract: real `UITabBarController` / `NSTabView`,
real sheets, real glass, Lua-composed widgets. Interaction galleries are a
**definition of done for motion UIKit and AppKit already have**, not a
backlog of new controls.

Working libraries: [60fps.design](https://60fps.design) (sheet, carousel,
empty, pull, badge, blur, keyboard, swipe) and [Mobbin](https://mobbin.com)
for static catalog / session / settings screens. Web-portfolio galleries
are not implementation references.

Compare a Simulator or AppKit clip of the **same control** to one 60fps
shot. If the system control already matches most of the shot, stop. The
rest is almost always custom drawing this project banned.

## Apply

| Pattern | Adventure Arena surface | Primitive |
|---|---|---|
| Coordinated sheet present/dismiss | Reading settings from the session | `ns.presentSheet` / `ns.dismiss` with system detents. Do not add a custom present animator. |
| Empty state with a next tap | Empty Discover catalog, empty Library | `ContentUnavailable` with one `Button` child, its `actions:` slot. Discover → Create; Library → Discover. |
| Hero carousel with peek | Discover featured row | Horizontal `ScrollView` + `scrollTargetBehavior="viewAligned"`. Page-style `TabView` on iOS when that PR lands. |
| Composer on material, keyboard-aware | Session command bar | `<GlassEffect>` around the field. `keyboardLayoutGuide` and `scrollDismissesKeyboard="interactively"` on iOS. `regular` system material is enough; do not take private liquid glass by name until a Lua example needs it. |
| Pull to refresh | Discover / Library lists later | `List` / `ScrollView` `refresh`. System `UIRefreshControl` only. |
| Swipe then confirm | Library row overflow | Trailing `Menu` on macOS; `List` swipe + `ns.confirm` or a detent sheet on iOS. |
| Hero bleed under chrome | Game detail cover, HowToPlay | `ignoresSafeArea="top"`. |
| Tab badge / now-playing | Stories in progress | Tab accessory (`NowReading`) on the bar. `UITabBarItem.badgeValue` is an iOS follow-up, not a reason to fake a tab bar. |

Celebration (first finished story, first scored command) is app Lua:
`SystemImage` + `ns.async` / `sleep`, same class as stars and bubbles.
Do not add `ns.Confetti` to `TAG_SCHEMA`.

## Do not apply

- Custom present/dismiss animators, 3D pushes, morphing tabs
- Pull-to-record, pinch-to-summarize, glass dock pickers
- Path-drawn compass rings (`Compass.etlua` is symbols + drag, not `CGPath` chrome)
- Per-row card shadows / cornerRadius APIs on panels
- Fake tab bars (`UISegmentedControl`) or custom nav chrome

Those last items are the widgets [`ios.md`](ios.md) already pushed into Lua
composition.

## Code map

| File | What to look at |
|---|---|
| `apps/adventure-arena/views/Adventures.etlua` | Featured carousel; empty catalog + Write an Adventure |
| `apps/adventure-arena/views/Bookshelf.etlua` | Empty library + Browse Discover; row menus |
| `apps/adventure-arena/views/Session.etlua` | Glass composer |
| `apps/adventure-arena/views/Tabs.etlua` | Real tabs + now-reading accessory |
| `apps/adventure-arena/Controller.lua` | `selectTab`, `presentSheet` wiring |
| `tests/adventure_arena_delight.test.lua` | Empty-state CTAs select the real tab |

When a primitive lands on iOS, record a clip of the AdventureArena-shaped
demo and compare it to one 60fps shot of that control.
