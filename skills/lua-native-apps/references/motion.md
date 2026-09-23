# Motion, gestures, and haptics

Keep interaction feedback native. There is no supported Lua frame loop or
general `view:animate(...)` API. Do not copy Reanimated worklets, use timer
loops that set a frame every tick, or claim that arbitrary property changes are
animated.

## Current capabilities

- UIKit/AppKit own navigation and sheet presentation transitions.
- `require("ui.haptics")` exposes the native haptic helpers documented in
  [`gestures.md`](gestures.md). Check `isAvailable()` and use feedback only for
  a meaningful action; headless tests must not depend on physical hardware.
- Gestures are limited to the recognizers and callbacks listed in
  [`gestures.md`](gestures.md). Do not invent velocity, drag, or long-press
  properties that are not in the current vocabulary.
- A general implicit animation API, matched geometry, and framework-wide
  Reduce Motion handling are tracked in
  [issue #10](https://github.com/corepunch/lua-objc/issues/10).

## Motion judgment

Use platform transitions for navigation and presentation. Keep dense tables,
static chrome, and frequently changing values quiet. Reserve additional motion
for feedback that clarifies a state change. If the user can interrupt a gesture,
the eventual framework API should carry gesture velocity into a native spring;
do not simulate this with Lua updates.

Before a framework motion API exists, prefer no extra animation to a custom
timer-driven effect. Respect the system's Reduce Motion setting whenever the
platform API exposes it; where it does not, avoid decorative movement.
