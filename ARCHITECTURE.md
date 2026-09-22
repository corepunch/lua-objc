# lua-objc Architecture

## Overview

lua-objc runs Lua scripts against native framework modules. Public UI
frameworks are Mach-O dylibs loaded by Lua; their declarative conveniences are
authored in Lua and embedded into the corresponding library at build time.

```
apps/<app>/             Lua Model, Controller, and views
src/host.c                  Tiny macOS executable loader
src/main.m                  AppKit translation-unit root and registration
src/appkit/*.m              Focused bridge fragments included by main.m
src/uikit/*.m               UIKit bridge root and focused fragments
src/shared/*.m              Shared Lua state, async, HTTP, JSON, error helpers
src/packager/packager.m     Mac packager: Lua + assets over HTTP/WebSocket
ios/LuaRuntime/            iPhone Simulator runtime (no app Lua inside)
build/AppKit.dylib          AppKit runtime + luaopen_AppKit
build/UIKit.dylib           UIKit compile-check (iOS SDK)
lua/embedded/*.lua          Declarative layers (AppKit embedded; UIKit streamed on iOS)
```

---

## Native module loading

`src/host.c` loads `build/AppKit.dylib` and calls its `lua_objc_main` entry
point. The framework owns the Lua state, AppKit bridge, layout metadata keys,
callback targets, and run loop. Keeping these in one image avoids splitting
native object identity or associated-object keys across the executable and a
plugin.

The runtime appends `build/?.dylib` to `package.cpath`. Consequently:

```lua
require("AppKit")  -- luaopen_AppKit in AppKit.dylib
require("UIKit")   -- luaopen_UIKit in UIKit.dylib, inside an iOS host
```

The build converts each `lua/embedded/*.lua` source into a byte-array header.
`luaopen_AppKit` evaluates that embedded chunk and returns its complete public
API table. There is no loose `AppKit.lua` or `IDEKit.lua` module that can
silently bypass native loading on macOS.

On the iPhone Simulator host, `luaopen_UIKitNative` is in-process and
`lua/embedded/UIKit.lua` is streamed from the Mac packager like application
Lua. See [docs/ios.md](docs/ios.md).

`AppKitNative` and `UIKitNative` are private implementation modules. Apps
use the public framework API; bridge tests may access native modules directly.

`make all` builds AppKit everywhere and also builds UIKit when an
iPhone Simulator SDK is available. `make uikit` requests that target
explicitly and fails with a focused message when Xcode platform support is
missing.

### iOS host and in-process reload

`src/host.c` cannot run UIKit. The iPhone Simulator product is a host app
(`LuaRuntime`) that statically links Lua 5.4.8 and the UIKit translation
unit. That `.app` is a runtime: it contains no application Lua, templates, or
images.

A Mac packager streams `.lua`, `.etlua`, and assets over HTTP and pushes
change events over WebSocket. The host calls `luaopen_UIKitNative` and
`require`s `UIKit.lua` from the packager (the `xxd`-embedded chunk in
`luaopen_UIKit` remains a dylib compile-check, not the Simulator load path).

A save **does not quit the host**. The process, scene, and window stay up.
Controller/view/asset updates replace `rootViewController` and keep `Model`.
`Model.lua` / `init.lua` recycle the in-process `lua_State` without
terminating `UIApplication`. Lua errors show an overlay. Native `.m` changes
are outside this loop.

The contract and operator commands live in [`docs/ios.md`](docs/ios.md).

---

## Layer 1 — Native runtimes and shared services

### AppKit runtime (`src/main.m` and `src/appkit/*.m`)

The AppKit bridge is a single Objective-C/C translation unit inside
`AppKit.dylib`. `src/main.m` owns shared constants and registration and includes
the focused fragments under `src/appkit/`. This preserves static shared state
without forcing readers to load an unrelated 4,000-line file. See
`src/README.md` for the subsystem map.

### UIKit runtime (`src/uikit_module.m` and `src/uikit/*.m`)

`src/uikit_module.m` embeds the public Lua layer and includes
`src/uikit/bridge.m`, the UIKit translation-unit root. That root owns UIKit
keys and module registration and includes focused fragments for layout, views,
controls, tables, metatables, and platform helpers.

Both runtime roots include `src/shared/lua_error.m` and
`src/shared/lua_async.m`, plus the state-agnostic boundary helpers in
`src/shared/lua_bridge_support.m`. The support layer owns native userdata and
converts scalar and collection values between Lua and Foundation without
owning a Lua state. The shared async layer supplies timers, HTTP, JSON,
coroutine-safe owner lookup, and cancellation. AppKit-created states use
closing owners; UIKit is loaded into a host-owned state and installs a
non-closing registry owner that detaches safely during `lua_close`.

### View construction

Lua components compose existing views. Native leaf constructors allocate
AppKit/UIKit objects and return `ObjCRef` userdata. Representative AppKit
construction paths are:

| Bridge function | AppKit class | Lua API |
|---|---|---|
| `bridge_vstack` | `NSView` (axis=vstack) | `ns.VStack` |
| `bridge_hstack` | `NSView` (axis=hstack) | `ns.HStack` |
| `bridge_hsplit` | `NSSplitView` (vertical=YES) | `ns.HSplit` |
| `bridge_vsplit` | `NSSplitView` (vertical=NO) | `ns.VSplit` |
| `bridge_separator` | `NSBox` (boxType=separator) | `ns.Separator` |
| `bridge_text_view` | `NSScrollView` + `NSTextView` | `bridge._textView()` |
| `bridge_tableview` | `NSScrollView` + `NSTableView` | `ns.List` |
| `bridge_window` | `NSWindow` | `ns.Window` |

Layout metadata (flexGrow, padding, fixedWidth, etc.) is stored as associated objects on the native view using `objc_setAssociatedObject`. This keeps all layout state alongside the view without subclassing.

### Layout engine

A custom flex-like layout engine is implemented entirely in C (`layout_recursive`, `measure_view`, `distribute_main_axis`). It runs synchronously when `bridge._layout(view)` is called.

**Pass 1 — Measure** (`measure_view`): each view reports its natural size given a constraint. Leaf views use current native intrinsic measurements, with width proposals for wrapping text. Stacks measure visible children and sibling spacing; HStack negotiates constrained widths. Previous layout frames do not become intrinsic minimums. Empty stacks measure zero, and flexibility is inherited from children on each axis.

**Pass 2 — Distribute** (`distribute_main_axis`): free space is distributed among children proportional to their `flexGrow` weight, clamped by `minWidth`/`maxWidth`.

**Pass 3 — Place**: each child is given a frame and `layout_recursive` descends into it.

`NSSplitView` divider thickness is accounted for in both hsplit and vsplit layout passes.
Native split controllers and navigation containers own their internal geometry.
The bridge uses native layout and constraints where appropriate (for example,
the workspace content host in `src/appkit/views.m`); the flex engine is not a
blanket replacement for Auto Layout.

## Object and state ownership

### Relationship to Apple JavaScriptCore

Issue #20 uses `JSManagedValue` as the useful Apple precedent. The analogy is
about ownership edges, not about embedding JavaScriptCore: a native object that
exports a script value must not blindly retain a value that can retain its
context. Apple solves that with conditional reachability reported through
`addManagedReference:withOwner:`; a managed value is kept alive while it is
reachable from either the script graph or the reported native owner, and is
otherwise cleared. See [Apple's JSManagedValue documentation](https://developer.apple.com/documentation/javascriptcore/jsmanagedvalue).

lua-objc applies the same design pressure using Lua-native mechanisms:

| JavaScriptCore idea | lua-objc mechanism |
|---|---|
| Script value | Lua closure, table, or native userdata handle |
| Native owner reported to the VM | Native target retains `LuaReg`; `Scope` retains the registration set |
| Conditional callback lifetime | `LuaReg` holds a registry ref and a weak `LuaStateOwner`; `dispose` is idempotent |
| Wrapper identity | Weak-valued handle intern table keyed by native pointer |
| Context lifetime | Explicit `LuaStateOwner` close/detach sequence |

This means the implementation follows the relevant JSC ownership principle,
but it does not provide JSC's garbage collector with a graph of arbitrary
Objective-C edges. A native callback can still participate in a Lua/native
cycle if it is left registered. Screens must close their `Scope`; models must
remain free of native handles; and callbacks must be state-bound rather than
using a process-global Lua state. The framework's current behavior and the
application rules are summarized in [application architecture](docs/agents/application-architecture.md).

### Native objects crossing into Lua

The shared boundary is implemented in `src/shared/lua_bridge_support.m`:

1. `push_objc` allocates a Lua userdata containing an `ObjCRef`.
2. `CFBridgingRetain(obj)` gives that handle one owning native reference.
3. Property reads use `__bridge id` to access the native pointer without
   transferring its ownership away from the handle.
4. The metatable's `__gc` calls `gc_objc`, which releases that reference with
   `CFRelease` and clears the pointer.

Native parents and strong properties can retain the same object independently.
Collecting a handle therefore does not mean unmounting or destroying its view.
Removing a child from a container likewise does not invalidate a surviving Lua
handle. Never use a native retain count to decide application lifecycle.

`push_objc` interns userdata in a weak-valued registry table keyed by the
native pointer. Reading the same object twice returns the same Lua handle, so
`rawequal` matches native identity and there is one Lua retain per live object.
A released handle (`ptr == NULL`) raises `native object has been released`
instead of crashing. Foundation scalars and collections are converted to Lua
values/tables; they are not live collection proxies. Native objects inside
those collections still use interned retained handles.

`tests/ownership.test.lua` verifies interned identity, native parent retention,
alias mutation, detachment, and reattachment. It observes Lua handle collection
and native usability; it does not instrument final native deallocation.
`tests/lifetime.test.lua` covers that directly with a sentinel associated
object (`_watchDealloc` / `_deallocCount` / `_deallocReset`): an unmounted view
deallocs after handle GC, a mounted view survives handle GC while its parent
retains it and deallocs after container clear, and window close disposes scope
callbacks without requiring native dealloc (windows are owned by `NSApp`).
It also covers two-window scope affinity, per-screen push/pop disposal, scope
pruning and idempotent close, timer cancellation on scope close, and
retired-state no-ops.

### Lua values crossing into native callbacks

A `LuaReg` roots one registry value against the originating `LuaStateOwner`.
Native targets retain the registration through an associated object. A Lua
`Scope` (`ui.scope` / `ns.Scope`) may also hold it. `dispose` unrefs against
the live, non-closing owner and is idempotent. Action targets, timers, HTTP
completions, watchers, and delegates invoke through `LuaReg` and never through
a process-global `gL`.

Each registration also remembers the `Scope` that was current at creation (a
registry ref released in `-dispose`/`-dealloc`). Pushing the closure re-enters
that scope first, so callbacks created inside an event handler bind to the
firing callback's scope rather than whichever window scope happens to be
global. A closed scope never accepts new registrations. `Scope:add` prunes
disposed entries, `Scope:close` is idempotent and marks the scope closed, and
`Scope.withScope` runs a function under an explicit scope. Navigation pushes
(`pushScreen`/`popScreen`) and UIKit sheets own per-screen scopes built with a
builder running inside the new scope; popping/dismissing closes the screen
scope. Both `AppKit.Window` and `UIKit.Window` close their scope on window
teardown automatically, so apps never call dispose by hand.

A registry closure can capture a controller, which holds a view handle, which
retains the native view. Waiting for that view's `dealloc` to unref its callback
cannot break this cycle. `Scope:close()` (window close, reload, or a
to-be-closed variable) unrefs the captures so Lua can collect the controller
even if native views still exist.

`LuaStateOwner.closing` is set before `lua_close`. Registrations that deallocate
during finalization skip the Lua API. The iOS host calls
`lua_objc_prepare_close` before replacing a state.

### Who closes `lua_State*`?

`lua_State*` is a C pointer. ARC does not free it automatically. The runtime
chooses an explicit closer, implemented through `LuaStateOwner` or the host:

| Context | Creator and closer | Callback lifetime |
|---|---|---|
| macOS app / headless script | `lua_objc_main` creates the state and a closing `LuaStateOwner`; owner deallocation calls `lua_close` | Async blocks and UI targets hold `LuaReg` against the owner |
| macOS `--preview` | The same main state and closing owner | No application run loop; preview does not wait for async completion |
| iOS host | `LRTApplicationController` creates and explicitly closes/replaces its state | UIKit installs a registry-retained non-closing owner for async lookup and cancellation |

Normal process termination can bypass orderly stack cleanup; do not use
process exit as the lifecycle mechanism for reusable screens or reloads.

`owner_for_state(L)` reads an unretained owner pointer from `lua_getextraspace`.
Lua 5.4 copies the main state's extraspace into new coroutines, so async bridge
calls resolve the same owner when invoked from a coroutine. Extraspace is a
lookup slot, not a strong reference. Scheduled work captures the Objective-C
owner instead of trusting a raw state pointer to remain valid.

The closing owner's `dealloc` marshals `lua_close` to the main queue when
released on a background queue. Closing a state runs userdata finalizers that
release UI objects. UI work and state access must remain serialized on the
main thread; ARC does not provide thread safety.

For iOS, the registry owner's `__gc` calls `detachState`, which cancels pending
work and sets `owner.L` to `NULL`. This occurs during host-driven `lua_close`;
it is not a separate pre-close sweep of every native callback. Async completions
check cancellation and avoid using a detached state. Registry finalization
must not be treated as a guaranteed ordering mechanism for all UI teardown.

### Cancellation and teardown requirements

`LuaStateOwner` tracks HTTP tasks and timers. `cancel` marks the owner cancelled,
cancels tasks, invalidates timers, and empties the pending list. Completions
untrack work and release registry references where the state remains live.
Strong block captures keep closing owners alive while work is pending; they
also mean ARC alone is not proof that cancellation releases every resource.

Before expanding reload or supporting multiple simultaneous states, implement
and test an explicit teardown sequence:

1. Stop accepting events for the retiring screen/state.
2. Dispose UI callbacks, delegates, watchers, and subscriptions against their
   original state; cancel outstanding async work.
3. Detach state access from surviving native objects and callbacks.
4. Release launch roots and native scene ownership as appropriate, then close
   the state exactly once on the main thread.

This sequence is the target contract. UI action targets invoke through `LuaReg`
and the originating `LuaStateOwner`; a callback from a retired state cannot
reach a new one. Retaining a native view never proves that its Lua callback
state is alive.

Language references: [Lua finalization](https://www.lua.org/manual/5.4/manual.html#2.5.3),
[registry references](https://www.lua.org/manual/5.4/manual.html#luaL_ref),
[coroutine extraspace](https://www.lua.org/manual/5.4/manual.html#lua_getextraspace),
and [Clang ARC semantics](https://clang.llvm.org/docs/AutomaticReferenceCounting.html).

---

## Layer 2 — Public Lua composition

The public APIs live in `lua/embedded/AppKit.lua` and `lua/embedded/UIKit.lua`.
AppKit is embedded at build time; UIKit is streamed by the iOS host. Both
compose native controls eagerly. Changing a model does not automatically
reevaluate the Lua function that constructed a view.

### Key functions

| Lua API | Bridge call | Notes |
|---|---|---|
| `ns.Window { ... }` | `bridge._window(...)` | Creates NSWindow, adds content VStack, triggers layout |
| `ns.VStack { ... }` | `bridge._vstack()` | Vertical flex container |
| `ns.HStack { ... }` | `bridge._hstack()` | Horizontal flex container |
| `ns.HSplit { ... }` | `bridge._hsplit()` | NSSplitView, left-right panes |
| `ns.VSplit { ... }` | `bridge._vsplit()` | NSSplitView, top-bottom panes |
| `ns.Separator()` | `bridge._separator()` | 1px NSBox rule |
| `ns.Text { ... }` | `bridge._textField()` | LuaTextField constructor with inherited KVC accessors |
| `ns.List { ... }` | `bridge._tableview(...)` | NSTableView in NSScrollView |
| `ns.Spacer()` | `bridge._spacer()` | flexGrow=1 filler |

### Layout props

All container and leaf views inherit bridge-owned layout accessors from the
`NSView` base extension. Ordinary Cocoa properties use the same KVC metatable:

```
padding, paddingHorizontal, paddingVertical
spacing, alignment
fixedWidth, fixedHeight
minWidth, minHeight, maxWidth, maxHeight
flexGrow, flexShrink, flexBasis
fillWidth, fillHeight
```

---

## IDE example (`apps/ide`)

The IDE is an intentionally small Lua application, not a separate framework.
It uses one native semantic sidebar for folder contents and one native editor
content pane. Folder selection, file watching, and saving stay in its
`Controller.lua`; file access and language detection stay in `Model.lua`.

### App layer

`lua/App.lua` is the root app controller. It does not mimic Swift inheritance;
it provides the same lifecycle role with a Lua object and callbacks:

- `App.args()` reads command-line arguments exposed by `src/main.m` as the
  global `arg` table.
- `App.new(spec)` creates a controller that can decide between a welcome scene
  and a workspace scene.
- `App:run()` opens the folder passed on the command line when present, and
  falls back to the welcome screen when no folder was provided.
- `App.recentStore(key)` persists recent folders/files under the user's app
  support directory.

The IDE now uses that layer to behave like VS Code on startup: open a folder
immediately when one was provided, or show a welcome screen with recent items
and an open-folder picker otherwise.

**Scene separation rule.** App components are etlua partials emitting view trees. The framework
instantiates the class returned by `init.lua`; its `createWindow()` method
(or the root `App` lifecycle) creates the window. `init.lua` itself stays thin
and does not self-start. Reusable view components do not create windows.

**MVC example layout.** Every standalone example lives under
`apps/<appname>/` with this layout:

```text
init.lua        ← requires and returns Controller class (framework instantiates)
Model.lua       ← data, queries, mutations (no ns.* calls)
Controller.lua  ← defines Controller class; wires model → views, owns actions
views/          ← etlua templates and reusable partials only
```

`init.lua` never self-starts. It returns the class; the framework calls
`class.new():createWindow()`. No module-level function controllers, no loose
table hierarchies. Flat `apps/<appname>.lua` shims are forbidden.

Larger apps follow Laravel/PHP-style composition: focused domain models own
queries, rules and mutations; small controllers coordinate one feature through
injected services and callbacks. Put them in `models/`, `controllers/`, and
`services/`; the root controller composes them. Test each feature with plain
data and fake IO independently of the window. Templates own all presentation,
including tips, category rows, and conditional content.

UI gaps belong in the framework. When native controls or layout do not meet
the SwiftUI-style contract, improve the shared implementation and its tests
instead of adding app-specific positioning or substitute controls.

The IDE example is organized as:

```text
apps/ide/
├── init.lua          # entry point
├── Model.lua         # file access and language detection
├── Controller.lua    # folder sidebar, editor, file watching, and saving
└── views/            # window configuration templates
```

That structure keeps app boot, scene selection, and UI composition separate
without introducing a second runtime or any non-Lua app scaffolding.

For the larger-app pattern used by Diskmap and Studio—feature-oriented MVC with
controller composition—see [docs/APP_STRUCTURE.md](docs/APP_STRUCTURE.md).

---

### XML view templates (`lua/ui/xml.lua`)

A cross-platform XML renderer sits between the app layer and the `ns.*` APIs.
Templates live in `apps/<app>/views/*.etlua`. The renderer:

- Applies etlua (`lua/vendor/etlua`, git submodule) to the XML source first,
  substituting `<%= expr %>` and `<% stmt %>` blocks.
- Parses the resulting XML with a pure-Lua SAX-style parser.
- Maps each tag to an `ns.*` call via a registry table. The platform module
  (`ns`) is injected by the caller — `<Label>` becomes `ns.Text` on AppKit
  and `ns.Label` (→ UILabel) on UIKit. No conditionals in the template.
- Custom tags: `xml.registry["MyTag"] = function(ns, attrs, children) ... end`
- API: `xml.render(src, data, ns)` and `xml.renderFile(path, data, ns)`

#### ref= attribute and named view handles

Any element may carry `ref="name"`. `xml.render` and `xml.renderFile` return
two values: the root view and a `refs` table `{ [name] = view }`. Controllers
use refs to attach callbacks and call methods on specific views without
scanning the tree manually:

```lua
local layout, refs = xml.renderFile("views/Window.etlua")
refs.messageList:onRowSelect(function(_, _, row) ... end)
refs.detailPane:clearContainer()
```

`ref` is consumed by the renderer and never forwarded to the native layer.

#### Window config from XML (NIB-style)

The `<Window>` tag captures window configuration declaratively, similar to
Xcode NIB/Storyboard files:

```xml
<Window title="Mail" width="940" height="520" minWidth="640" minHeight="400">
    <Toolbar>
        <ToolbarItem id="compose" label="Compose"
                     icon="square.and.pencil" tooltip="New Message" />
    </Toolbar>
    <HSplit>
        <List ref="mailboxList" ... />
    </HSplit>
</Window>
```

`xml.renderFile` detects a `<Window>` root and returns `(config, refs)` instead
of `(view, refs)`. The config table includes title, dimensions, toolbar items,
and other window properties. Controllers pass it to `ns.Window(cfg)`. Toolbar
action strings (e.g., `action="compose"`) resolve to Controller methods via an
ACTIONS table:

```lua
local ACTIONS = {
    compose = function(self) self:compose() end,
}
for _, item in ipairs(cfg.toolbar or {}) do
    if item.action and ACTIONS[item.action] then
        local fn = ACTIONS[item.action]
        item.action = function() fn(self) end
    end
end
```

#### Template inheritance (Blade/Twig style)

Child templates can extend a parent layout, defining blocks that the parent
renders via `yield()`:

```lua
-- Child: apps/hello/views/Window.etlua
<% extends("views/AppWindow.etlua", { title = "Hello", width = 480 }) %>
<% block("content", [[
    <VStack padding="24">
        <Label text="Hello from Lua" size="24" />
    </VStack>
]]) %>

-- Parent: views/AppWindow.etlua
<Window title="<%= title %>" width="<%= width %>">
    <%= yield("content") %>
</Window>
```

The framework resolves relative paths from the child template's directory.

#### Partials

Include reusable sub-templates with `partial()`:

```lua
<%= partial("views/partials/SimpleList.etlua", {
    ref = "employeeList",
    columns = {
        { id = "name", title = "Name" },
        { id = "role", title = "Role" },
    },
}) %>
```

Partials receive their own data context and resolve paths relative to their
own file location.

#### View description format (`lua/ui/viewdesc.lua`)

`lua/ui/viewdesc.lua` parses descriptions and computes positional diffs.
Its `apply` function is a no-op. It is not connected to the eager constructors
as a working renderer and does not yet preserve native identity through keyed
reconciliation.

`lua/ui/template.lua` is the working retained etlua boundary renderer. `Template.new`
mounts into a template-provided host; `update(data)` evaluates XML and plain bindings.
Unchanged descriptions reuse native identity while action dispatch points to current
callbacks. Changed descriptions render under a new Scope, replace the old subtree,
and dispose its registrations. Failed rendering leaves the previous tree mounted.
Parent scopes dispose nested mounts. Applications bind data and actions only.

This boundary renderer does not yet provide keyed child reuse, automatic dependency
tracking or observable invalidation. `ui.viewdesc` remains a separate experimental
positional-diff module, not its runtime. A future keyed renderer should extend the
shared ownership contract rather than add feature-specific subtree mutation hooks.

#### Templates and reusable views

Templates provide the shared XML vocabulary and etlua partials provide reusable
view structure. Keep both in `views/`. Controllers own actions and connect
model data to rendered refs; they do not assemble view trees. Use etlua loops
for repeated siblings. Framework-level Lua composition such as `ForEach` and
`Group` remains available to the framework, but application screens should use
etlua templates and partials. Constructors should not run inside template
interpolation.

---

## IDE layout (`apps/ide`)

```
ns.Window
└── NSSplitViewController
    ├── NSSplitViewItem.sidebar  → OutlineView (source-list folder tree)
    └── NSSplitViewItem.content  → TextEditor (editable file content)
```

---

## --preview CLI mode

```
./lua-objc --preview [--width=N] [--height=N] [--out=path.png] file.lua
```

The implementation is in `src/main.m`, with `offscreen_render` in
`src/appkit/platform.m`. It uses the launcher's main Lua state, temporarily
replaces `ns.Window` / `ns.Preview` with stack construction, executes the script,
and requires a returned native view. It lays out that view and renders PNG
without running the application event loop. Async-loaded data is not awaited.

This path does not instantiate a Controller class returned by a thin app entry
point. Use `--screenshot` or `--dump-layout` for `apps/<app>/init.lua` apps;
those paths exercise framework startup and real window geometry. There is no
current `canvas_state_create`, `bridge_eval`, or isolated IDE canvas subsystem.

---

## File watcher

`bridge._watchFile(path, callback)` uses `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`. One stream per path, stored in `gFileWatchers` (global `NSMutableDictionary`). Callbacks fire on the main queue. Passing `nil` as callback cancels the watcher.

---

## Key design constraints

- **One AppKit runtime image**: all AppKit bridge and host state lives in
  `AppKit.dylib`; `lua-objc` itself is only a loader.
- **Public module delivery**: AppKit Lua helpers are embedded in the native
  module; the iOS development host streams UIKit helpers from the packager.
- **Per-view layout state**: associated objects store layout metadata; base
  extensions expose accessors and native subclasses supply semantics as needed.
- **Explicit state ownership**: closing owners wrap `lua_close` on macOS;
  the iOS host closes its state. Async callbacks resolve owners via extraspace.
- **Native geometry authority**: flex layout owns framework stacks; native
  split, navigation, and hosting containers retain their layout responsibilities.
- **Source folders express responsibility**: platform and shared fragments stay
  in their own folders while sharing one platform runtime. See [src/README.md](src/README.md).

## Review priorities and acceptance criteria

| Priority | Evidence in the current implementation | Completion criterion |
|---|---|---|
| Callback registration lifetime | `LuaReg` + `Scope`; UI targets do not use `gL` | Replacement and `Scope:close()` unref captures; retired-state callbacks are no-ops |
| Deterministic state shutdown | `LuaStateOwner` cancellation and iOS registry finalization exist, but no common UI pre-close disposal pass | Explicit main-thread shutdown; pending work, late callbacks, and repeated iOS reload covered without stale-state access |
| Retained rendering | Eager public constructors; `viewdesc.apply` is empty | Keyed insert/remove/move/reuse preserves focus, selection, local state, and releases removed callbacks |

Keep the existing folder split. Extract further subsystems when they have a
cohesive responsibility; moving all `.m` files into one directory would not
resolve any of these lifetime or rendering gaps. Add deterministic headless
regressions for each implementation step. Verify native interaction and reload
in a running host when those behaviors change; compilation alone cannot prove
them.
