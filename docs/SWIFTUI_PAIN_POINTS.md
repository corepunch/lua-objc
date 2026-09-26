# Swift / SwiftUI pain points (and how lua-objc answers them)

This document catalogs what working Apple-platform developers actually complain about when they use Swift, SwiftUI, and Xcode. It is a product brief, not a dunk on Apple: the complaints are the gaps lua-objc should close so people have a reason to try a Lua + AppKit/UIKit stack.

Sources: Apple Developer Forums, Swift Forums, Reddit (`r/SwiftUI`, `r/iOSProgramming`), blogs (Hacking with Swift, Thoughtworks, Medium production postmortems), and X posts from practicing iOS/macOS engineers. The same themes have persisted from SwiftUI's 2019 launch through 2026.

Status legend for lua-objc:

- **Done** — already part of the advertised loop (hot reload, native controls, no per-edit compile).
- **Partial** — the architecture can address it; coverage or polish is incomplete.
- **Open** — a deliberate lure item we should plan, measure, and ship against.

Related docs: [SWIFTUI_PARITY_PLAN.md](SWIFTUI_PARITY_PLAN.md), [ios.md](ios.md), [ARCHITECTURE.md](../ARCHITECTURE.md).

---

## 1. Xcode Simulator is unreliable and slow

**What people say**

- Simulator fails to boot: `Unable to boot the Simulator`, `launchd_sim` crashes, `could not bind to session`, black/white screens, stuck Apple logo.
- First boot of a new runtime is extremely slow (dyld shared cache). Debug-attached launches can take 30 seconds to several minutes.
- Idle high CPU / fans / heat from crash-loops (`MercuryPosterExtension`, SpringBoard, `SimRenderServer`, `diagnosticd` log floods).
- New OS runtimes often regress (iOS 18 / 26 simulators worse than the previous one).
- WebViews and heavy screens freeze in the simulator.
- Ritual workarounds: `simctl erase all`, disable Debug Executable, wipe DerivedData, prefer older runtimes.
- CI runners frequently cannot start simulators at all.

**Why it hurts:** the official iteration path is “compile → install → wait for Simulator → attach LLDB”. Any flake in that chain kills flow.

**lua-objc angle**

| Response | Status |
| --- | --- |
| macOS path skips the iOS Simulator entirely: `./lua-objc apps/<app>` runs a real AppKit process. | Done |
| iOS host is a long-lived Simulator *or device* process that streams Lua/assets and reloads in place — the host does not quit on every edit (`ios.md`). | Done |
| Headless `--screenshot` / `--dump-layout` and Lua tests do not need a booted SpringBoard for every check. | Done |
| Document a “never reboot the sim to see a UI change” guarantee and keep the iOS host from depending on PreviewShell. | Partial |
| Track Simulator-only failures separately from framework bugs so we do not inherit Xcode's boot lottery. | Open |

---

## 2. Compilation and iteration are too slow

**What people say**

- Incremental Swift builds still take tens of seconds to minutes for a one-line change.
- `the compiler is unable to type-check this expression in reasonable time` — especially large `body` views and `+` / string-interpolation chains.
- Type checker can go super-linear or exponential on inference.
- “Planning Swift module” / emit-module stays expensive even with no source change; worse in multi-module / SPM graphs.
- Whole-module vs incremental, batching, and settings like User Script Sandboxing can silently serialize compiles.
- New Xcode / Swift versions often *regress* build times (Swift 6 / Xcode 16 called out repeatedly).
- Bridging headers and generated `-Swift.h` in ObjC++ files add minutes.
- Result: the edit → compile → preview/sim loop is the opposite of hot reload.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Lua has no Swift type-checker in the hot path. Edit a `.lua` / `.etlua` file and reload. | Done |
| In-process iOS reload: save file → host reloads views without quitting or relinking. | Done |
| Keep native code (ObjC bridge) in a stable binary so UI work never waits on `swiftc`. | Done |
| Benchmark the loop: time-to-first-pixel after a one-line view change vs Xcode incremental + Simulator attach. Publish numbers. | Open |
| Guard against accidentally pushing work back into a compile (heavy generated Swift, SPM graphs for demos). | Open |

---

## 3. SwiftUI Previews lie or break

**What people say**

- Previews work until you add navigation, environment objects, async, Core Data, SPM, or “breathe on the project.”
- `Cannot preview in this file`, PreviewShell crashes, hanging spinners, 30s thunk timeouts.
- Third-party packages (Firebase, Maps, …) often kill previews.
- Previews rebuild far more of the app than they should; script phases without declared outputs loop rebuilds.
- Packages: missing target descriptions, wrong `Bundle.module` paths.
- Workarounds: Legacy Previews Execution, wipe preview caches, delete DerivedData, restart Xcode.
- Many teams abandon Previews and only trust the Simulator — which is itself slow (see §1).

**lua-objc angle**

| Response | Status |
| --- | --- |
| There is no PreviewShell. The thing you run *is* the app. | Done |
| `--screenshot` and `--dump-layout` are deterministic previews of the real native tree. | Done |
| Do not invent a second renderer for “preview mode” that diverges from production. | Done (principle) |
| Make screenshots / layout dumps cheap enough that agents and humans use them instead of Xcode Canvas. | Partial |

---

## 4. Performance and layout unpredictability

**What people say**

- Large lists / feeds stutter; cells destroyed too aggressively; `.task` cancelled as rows scroll off. `UICollectionView` still wins for big or heterogeneous lists.
- Layout via proposed-size negotiation is unpredictable: floating views, custom sidebars, grids, doubled safe areas.
- Animations hitch; some argue SwiftUI animations run in-process without Core Animation's render-server independence, so a blocked main thread stalls UI that UIKit would keep moving.
- Weaker scroll control than UIKit (pixel offset, velocity, `willEndDragging`-style hooks).
- macOS SwiftUI often worse than iOS (drag-and-drop, windows, text, scrolling).

**lua-objc angle**

| Response | Status |
| --- | --- |
| Lists, tables, and collection-style UI sit on real `NSTableView` / `UITableView` / `UICollectionView`, not a virtualized SwiftUI `List`. | Partial |
| Layout is native Auto Layout / stack views, not AttributeGraph size negotiation. | Partial |
| Animations can use Core Animation / UIView animation so they are not tied to Lua frame callbacks. | Partial |
| Document when to drop to a native table vs a declarative stack; add scroll-performance fixtures to parity tests. | Open |
| Expose enough scroll / gesture control that people do not immediately wrap UIKit themselves. | Open |

See [tableview_swiftui.md](tableview_swiftui.md) and the parity suite.

---

## 5. State, data flow, and architecture fog

**What people say**

- Too many wrappers: `@State`, `@Binding`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Observable`, `@Query`. Wrong choice → surprise redraws, leaks, stale UI.
- Views become god objects: networking and business rules live in `body`.
- `onAppear` / `.task` fire too often or at the wrong time and get used as lifecycle.
- AttributeGraph “magic” is hard to debug compared with a view controller.
- Observation + Combine + Swift Concurrency produce races that are painful in UI apps.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Recommended MVC: `Model.lua` (pure data), `Controller.lua` (actions, lifetimes), `views/` (etlua). Documented in agents + examples. | Done |
| Native views own the on-screen objects; Lua owns state tables you can print and test. | Done |
| No property-wrapper zoo. Bindings are explicit tables / callbacks. | Done |
| Keep pushing examples away from “logic in the template.” Add a short “state ownership” page if agents start stuffing IO into etlua. | Partial |
| Spell out screen appear/disappear vs SwiftUI `onAppear` so people do not recreate that footgun. | Open |

---

## 6. Navigation is a moving target

**What people say**

- API churn: `NavigationView` → `NavigationStack` / `NavigationPath` / `navigationDestination`, deprecated link styles every WWDC.
- Programmatic navigation and deep linking historically broken or limited (row must be visible, only N levels, frozen stacks, path resets).
- Hard to split flows across coordinators the way `UINavigationController` allows.
- No presentation / dismissal completion callbacks.
- Toolbar placement, title flicker, sheets that are not animatable the AppKit/UIKit way.
- Mixing UIKit navigation with SwiftUI breaks across OS point releases.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Navigation is `UINavigationController` / `NSViewController` presentation — the model that has worked since iOS 2. | Partial |
| Controllers can push/pop and get completion-equivalent hooks from UIKit/AppKit. | Partial |
| Deep links are “set controller state, rebuild or push the right screen” — not a parallel NavigationPath type. | Partial |
| Finish a documented navigation + sheet + toolbar recipe that does not change every OS. | Open |
| Deep-link tests (cold start to screen N, pop to root) in the iOS host. | Open |

---

## 7. Incomplete or inflexible UI APIs

**What people say**

- Still awkward vs UIKit: camera / AVFoundation overlays, rich text, custom collection layouts, fine-grained gestures, keyboard focus timing, pull-to-refresh customization, some toolbar/search behavior.
- `List` customization: two inches past the default and it is workarounds.
- No clean design-system primitive; modifiers reapplied everywhere.
- macOS drag-and-drop has been through multiple SwiftUI API revisions and is still hard.
- New OS versions introduce visual regressions (glass/morph menus, Form/List padding, search scopes vanishing, tab bar disappearing with alerts).

**lua-objc angle**

| Response | Status |
| --- | --- |
| Missing control? Drop to the real UIKit/AppKit class through the bridge instead of waiting for a SwiftUI wrapper. | Partial |
| Design tokens live in Lua tables / shared XML attributes, not a pile of view modifiers. | Partial |
| Parity plan already tracks widget coverage (`docs/parity/`). | Partial |
| Treat “camera, rich text, DnD, keyboard focus, refresh control” as lure features with fixtures, not blogware. | Open |
| Prefer wrapping a mature native control over reimplementing SwiftUI's half-finished one. | Open (principle) |

---

## 8. Tooling, docs, and day-to-day DX

**What people say**

- Xcode indexing, SourceKit, opaque errors, weak SwiftUI view-hierarchy debugging vs UIKit.
- Official docs thin on the unhappy path; Stack Overflow is the real manual.
- Large view-builder errors are useless (`ambiguous without more context`, type-check timeout) instead of pointing at the typo.
- Previews + Simulator + compiler together make the “fast declarative loop” slower than UIKit for many teams.
- LLMs struggle more with SwiftUI than with UIKit corpora.
- Testing SwiftUI (navigation, sheets, focus) is weaker than UIKit.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Lua parse/runtime errors name a file and line. Templates are XML + Lua, not a giant opaque `some View`. | Done |
| Headless tests, screenshots, and layout dumps are first-class (`make test`, `--screenshot`, `--dump-layout`). | Done |
| Agent docs (`docs/agents/`) are written so an LLM can produce a tested app without Xcode Canvas. | Partial |
| Keep error messages from the XML parser and bridge specific (tag, attribute, expected type). | Partial |
| Publish a “debug the native tree” recipe (`--dump-layout`, view debugger on the real AppKit/UIKit hierarchy). | Open |

---

## 9. Maturity, compatibility, and hybrid apps

**What people say**

- SwiftUI still feels like a perpetual beta after seven years: API churn, shims for old OS versions, features gated on iOS 16/17/18.
- Production apps are hybrid UIKit + SwiftUI; the boundary is painful (sizing, safe area, two state systems, debugging).
- Apple's own apps and samples show the same bugs.
- Seniors keep UIKit for navigation, lists, camera, and performance-critical surfaces and use SwiftUI only for simple screens.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Target AppKit/UIKit primitives that have been stable for a decade+. | Done (principle) |
| One state system (Lua) and one view system (native). No hosting-controller sandwich unless the user opts in. | Partial |
| Support a wide deployment target without “this modifier is iOS 18 only.” | Partial |
| Say clearly: lua-objc is not “SwiftUI in Lua”; it is declarative Lua *on* UIKit/AppKit so you inherit UIKit maturity. | Open (messaging) |

---

## 10. Language-level Swift friction

**What people say**

- Slow type checker (see §2).
- Actors / isolation / concurrency deadlocks that are hard to observe in UI apps.
- Macros (SwiftData, Observation) hide complexity and crash or change behavior across OS versions with little documentation.
- SwiftData compared to SwiftUI: great in demos, sharp edges in production.

**lua-objc angle**

| Response | Status |
| --- | --- |
| Persistence and networking stay ordinary Lua + native frameworks the user chooses (files, SQL, URLSession), not a mandatory macro stack. | Partial |
| Concurrency model for the UI thread is explicit: native main queue + Lua callbacks, not implicit actor hopping in `body`. | Partial |
| Do not grow a SwiftData-shaped “magic persistence” layer until the UI loop is undeniably faster and more reliable than Xcode's. | Open |

---

## How to use this list

1. **Marketing / README** — lead with §1–§3 (Simulator, compile times, Previews). Those are felt on day one.
2. **Roadmap** — treat §4 lists/scroll, §6 navigation+deep links, and §7 camera/keyboard/DnD as the features that convert a curious SwiftUI refugee.
3. **Parity work** — every Open row should become a fixture in `docs/parity/` or a test under `test/` / `tests/`.
4. **Honesty** — do not claim SwiftUI-level sugar we do not have. Claim a shorter loop, real native controls, and a state model you can print.

The pattern developers repeat: SwiftUI is fast for the first 80–90% of a screen, then they hit a wall (layout, navigation, list, preview, or compile) that UIKit would have made explicit. lua-objc should make that last 10% a native control plus a Lua reload, not another week of workarounds.
