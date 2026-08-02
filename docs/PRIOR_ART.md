# Prior Art & Reference Projects

This document catalogs projects that overlap with lua-objc's goals —
SwiftUI-like declarative APIs backed by real native controls — and
identifies specific patterns worth adopting or studying.

---

## 1. SwiftCrossUI

**Repo:** https://github.com/stackotter/swift-cross-ui
**Language:** Swift 5.10+
**Platforms:** macOS (AppKit), iOS/tvOS (UIKit), Windows (WinUI), Linux (GTK4/GTK3)

A SwiftUI-like framework with a clean backend abstraction. Write once,
render natively on every platform.

### Architecture

```
SwiftCrossUI Core (platform-independent)
    ├── AppKitBackend   (macOS)
    ├── UIKitBackend    (iOS/tvOS)
    ├── WinUIBackend    (Windows)
    └── GtkBackend      (Linux)
```

- `DefaultBackend` auto-selects at compile time based on target OS.
- Backend override via `SCUI_DEFAULT_BACKEND` env var for cross-testing.
- Experimental backends: Qt, LVGL (embedded), Curses (CLI).

### Key Takeaways for lua-objc

- **Backend protocol pattern.** Each platform implements a protocol/interface
  that the core framework calls into. This is exactly how lua-objc should
  structure AppKit vs UIKit support — a shared Lua API that dispatches to
  platform-native bridge calls.
- **Feature parity matrix.** They maintain explicit per-backend feature
  tracking. We should do the same to know which widgets work on which
  platform.
- **Compile-time backend selection.** We could use `__APPLE__` / `_WIN32`
  style flags, but our runtime dispatch via `require("AppKit")` vs
  `require("UIKit")` is already cleaner.

---

## 2. Limekit

**Repo:** https://github.com/mitosisX/Limekit
**Language:** Lua (bridged through Python/PySide6)
**Platforms:** Windows, macOS, Linux

Lua GUI framework with 40+ wrapped Qt widgets, Material Design theming,
and a pure Lua API. Ships with `Limer`, a deployment tool.

### Architecture

```
Lua App Code
    ↓
lupa bridge (Lua ↔ Python)
    ↓
PySide6 (Qt) widgets
    ↓
Native rendering
```

### Key Takeaways for lua-objc

- **40+ widgets is achievable from Lua.** Limekit proves a Lua GUI
  framework can have real breadth — buttons, tables, charts, calendars,
  split views, modals, etc. This validates that lua-objc can aim for
  comprehensive coverage.
- **Theme system design.** They ship Material, Light/Dark, and Fluent themes.
  We should plan a theming API from the start, even if v1 is simple.
- **Deployment tooling matters.** `Limer` packages apps for distribution.
  At some point we need a `make bundle` or similar for lua-objc apps.
- **What NOT to do.** Limekit bridges through Python (lupa), adding a
  runtime dependency and performance overhead. Our direct ObjC bridge
  via FFI is fundamentally better for this reason.

---

## 3. Yue

**Docs:** https://libyue.com/docs/latest/lua/index.html
**Language:** Lua API (C++ core)
**Platforms:** macOS, Windows, Linux

A native UI library with Lua bindings. Clean, minimal API surface.
Widgets include button, label, table, entry, scroll, tabs, window,
tray, dialog, webview, and more.

### Key Takeaways for lua-objc

- **Cleanest Lua GUI API.** Yue's Lua API is the most idiomatic —
  constructor tables, method chaining, event callbacks via functions.
  This is the API style we should benchmark against.
- **Window as first-class object.** Their `Window` class handles title,
  size, menu bar, toolbar, and tray in one unified API. We should
  consolidate our window creation similarly.
- **TableModel pattern.** They expose a `TableModel` for data-driven
  table views, which is analogous to our `replaceRows()` API. Worth
  studying their model/view separation.
- **WebView integration.** They embed a native webview using the system
  browser engine. This could be a future lua-objc feature.

---

## 4. Valdi (Snapchat)

**Repo:** https://github.com/snapchat/valdi
**Language:** TypeScript → native views
**Platforms:** iOS, Android, macOS

A cross-platform UI framework used in production at Snapchat for 8+ years.
Compiles declarative TypeScript to platform-native views — no webviews,
no JS bridges.

### Architecture

```
TypeScript Components
    ↓ (compile-time codegen)
Kotlin / ObjC / Swift bindings
    ↓
Platform-native views
```

### Key Takeaways for lua-objc

- **Compile-time bridge generation.** Valdi auto-generates type-safe
  bindings between TypeScript and native platforms. We could generate
  Lua↔ObjC bridge code from a schema instead of hand-writing it.
- **Polyglot modules.** Performance-critical code can be written in
  C++, Swift, or Kotlin alongside the TypeScript. Our `.m` files serve
  the same role — native code for things Lua can't do.
- **Embed native in declarative, and vice versa.** Drop native views
  into Valdi layouts, or use Valdi components inside native view
  hierarchies. We should support this bidirectional embedding.
- **Production validation.** 8 years at Snap scale proves that
  declarative→native compilation is a viable architecture for
  large apps.

---

## 5. Qt/QML

**Docs:** https://qt.io
**Language:** QML (JavaScript logic) + C++
**Platforms:** Everything (desktop, mobile, embedded, MCU)

The mature reference for declarative UI markup that maps to native widgets.
QML is a declarative language; Qt Quick Controls provide pre-built widget
sets with native look-and-feel.

### Architecture

```
QML Files (declarative UI)
    ↓
Qt Quick (scene graph rendering)
    ↓
Qt Widgets or Qt Quick Controls (native-styled)
```

### Key Takeaways for lua-objc

- **QML is the closest analog to our XML templates.** Both define UI
  declaratively and map to native controls. We should study QML's
  property binding system — when a data value changes, the UI updates
  automatically.
- **Qt Quick Controls.** They provide pre-styled widget sets that look
  native on each platform. Our XML registry (VStack, HStack, List, etc.)
  serves the same role.
- **Model/View separation.** Qt's model/view architecture (models,
  views, delegates) is battle-tested. Our `Model.lua` + `Controller.lua`
  + `views/` pattern already follows this — we should formalize it.
- **Property bindings.** QML's `property alias` and binding expressions
  keep UI in sync with data without manual updates. We could add a
  lightweight binding system to Lua.
- **What NOT to do.** Qt is massive (~100MB). Our advantage is tiny
  footprint — a single dylib and Lua scripts. Don't chase Qt's scope.

---

## 6. SwiftOpenUI

**Repo:** https://github.com/codelynx/SwiftOpenUI
**Language:** Swift
**Platforms:** macOS (real SwiftUI), Linux (GTK4), Windows (Win32/D2D)

Re-implements SwiftUI's API surface on non-Apple platforms. Same Swift
source compiles to real SwiftUI on macOS, GTK4 on Linux, Win32 on Windows.

### Key Takeaways for lua-objc

- **Same API, different backends.** The pattern of writing one view
  definition and rendering natively on each platform is exactly what
  we do with `ns.VStack` producing NSTableView on macOS and UIStackView
  on iOS.
- **45 views, 40 modifiers.** They track exact SwiftUI parity. We should
  maintain a similar coverage matrix.
- **Backend as a module.** Each backend is a separate Swift module
  imported conditionally. Our `require("AppKit")` / `require("UIKit")`
  is the Lua equivalent.

---

## 7. WaterUI

**Repo:** https://github.com/nicholasgasior/waterui
**Language:** Rust
**Platforms:** Apple (SwiftUI backend), Linux (GTK4 backend)

SwiftUI-inspired Rust framework with fine-grained reactivity (Vue-like)
instead of virtual DOM diffing.

### Key Takeaways for lua-objc

- **Reactive updates without virtual DOM.** They use a fine-grained
  reactivity system — only the affected widget re-renders when data
  changes. This is more efficient than re-rendering entire subtrees.
  We could adopt a simpler version: `list:replaceRows(data)` already
  does this for tables.
- **Backend-first development.** They built the SwiftUI backend first,
  then added GTK4. This validates our approach of nailing AppKit/UIKit
  before considering other platforms.

---

## 8. OpenSwiftUI

**Repo:** https://github.com/openswiftuiproject/openswiftui
**Language:** Swift, C, C++, ObjC
**Platforms:** Linux, Windows (macOS uses real SwiftUI)

Open-source reimplementation of SwiftUI's internals. Not a framework
for building apps — a research project to understand SwiftUI's actual
implementation.

### Key Takeaways for lua-objc

- **SwiftUI internals.** Read their source to understand exactly what
  SwiftUI does under the hood — layout negotiation, state management,
  view identity, diffing. This helps us replicate the right semantics.
- **Debugging tool.** If something behaves unexpectedly in our
  SwiftUI-like API, check OpenSwiftUI to see what the real implementation
  does.

---

## 9. QuillUI

**Repo:** https://github.com/Lore-Hex/QuillUI
**Language:** Swift
**Platforms:** Linux (GTK/Qt backends), macOS (real Apple frameworks)

Apple Swift app compatibility layer for Linux. Reimplements AppKit, UIKit,
SwiftData, and SwiftUI shapes for Linux via GTK and Qt backends.

### Key Takeaways for lua-objc

- **Scope reference.** They attempt to reimplement AppKit + UIKit + SwiftUI
  for Linux. This shows the full scope of what "complete native coverage"
  means. We should study their feature matrix to prioritize our roadmap.
- **Dual backend discipline.** They maintain GTK and Qt backends in parallel
  to enforce abstraction — no backend specifics leak into the compatibility
  layer. We should enforce the same discipline between AppKit and UIKit.
- **Paint layer.** Their `QuillPaint` provides a custom paint system on top
  of GTK for pixel-perfect macOS-style rendering. Interesting for future
  customization.

---

## 10. Nucleus

**Site:** https://nucleusframework.dev/
**Language:** Kotlin + Compose Multiplatform
**Platforms:** macOS, Windows, Linux

Desktop apps built on Kotlin and Compose Multiplatform (Skia rendering).
30+ runtime modules for OS integration: notifications, tray, dark mode,
global hotkeys, taskbar, etc.

### Key Takeaways for lua-objc

- **OS integration is what makes apps feel native.** They wrap platform
  APIs (notifications, tray icons, dock badges, dark mode detection) behind
  a clean cross-platform API. We should do the same — `ns.Notification`,
  `ns.Tray`, etc.
- **Lightweight matters.** They highlight that Electron apps are 100s of
  MB while theirs is tiny. Our Lua + native bridge approach is even
  lighter.
- **GraalVM native image.** They can compile to standalone binaries. We
  could offer `luac` compilation + dylib bundling for distribution.

---

## 11. react-native-gtkx

**Repo:** https://github.com/itsmepetrov/react-native-gtkx
**Language:** React Native (JavaScript) → GTK4
**Platforms:** Linux

React Native components rendered as real GTK4/Adwaita widgets. Uses the
React reconciler to drive native GTK widget trees. Navigation backed by
real `Adw.NavigationView`.

### Key Takeaways for lua-objc

- **Same API, different renderer.** They alias `react-native` imports to
  `react-native-gtkx` — same component API, different backend. This is
  exactly our `ns.VStack` pattern.
- **Navigation on real widgets.** Their navigators use real Adwaita
  navigation widgets, not custom-drawn ones. We should do the same —
  real `NSSplitViewController`, not simulated split views.

---

## 12. MoonNuklear

**Repo:** https://github.com/stetre/moonnuklear
**Language:** Lua (via C bindings)
**Platforms:** Linux, macOS, Windows

Lua bindings for the Nuklear immediate-mode GUI toolkit. Contrasting
approach: no retained widget tree, no native controls — everything is
drawn every frame.

### Key Takeaways for lua-objc

- **Immediate mode as contrast.** Nuklear redraws everything each frame.
  Our retained-mode approach (real widgets that persist) is better for
  accessibility, native look-and-feel, and integration with OS features.
  This validates our architectural choice.
- **Minimal Lua GUI works.** Shows that Lua can drive GUI code effectively,
  even if the rendering approach is different.

---

## Summary: What to Steal

| From | Steal | Why |
|------|-------|-----|
| SwiftCrossUI | Backend protocol pattern | Clean multi-platform dispatch |
| SwiftCrossUI | Feature parity matrix | Track widget coverage per platform |
| Limekit | Widget breadth target | 40+ widgets is achievable |
| Limekit | Theme system design | Plan theming from v1 |
| Yue | Lua API idioms | Most idiomatic Lua GUI API |
| Yue | TableModel pattern | Formalize model/view separation |
| Valdi | Compile-time bridge codegen | Reduce hand-written bridge code |
| Valdi | Polyglot module pattern | Native code for performance-critical paths |
| Qt/QML | Property binding system | Auto-sync UI with data changes |
| Qt/QML | Model/View/Delegate | Formalize our MVC pattern |
| SwiftOpenUI | Coverage tracking | 45 views, 40 modifiers — know your gaps |
| WaterUI | Fine-grained reactivity | Update only changed widgets |
| OpenSwiftUI | SwiftUI semantics reference | Understand what we're replicating |
| QuillUI | Dual-backend discipline | Enforce AppKit/UIKit abstraction boundary |
| Nucleus | OS integration APIs | Notifications, tray, dark mode |
| react-native-gtkx | API aliasing pattern | Same API, swappable renderer |
| MoonNuklear | Architecture validation | Retained mode > immediate mode for native feel |
