---
name: maintain-lua-objc-framework
description: Maintain and extend lua-objc native framework code in Objective-C `.m` files. Use when changing AppKit or UIKit bridge primitives, native controls, userdata/KVC behavior, layout, tables or outlines, callbacks, async Lua state ownership, HTTP/JSON services, module registration, source organization, native build rules, or headless framework tests.
---

# Maintain the lua-objc Framework

Keep application behavior in Lua. Change native code only for framework
infrastructure, platform integration, or a real AppKit/UIKit-backed leaf
control.

## Locate the subsystem

Read `src/README.md`, then search for the exact bridge symbol:

```sh
rg -n 'bridge_name|NativeClass|publicLuaName' src lua tests
```

Open only the matching fragment:

- `src/main.m` — AppKit constants, registration, host entry point
- `src/appkit/` — AppKit implementation fragments
- `src/uikit/bridge.m` — UIKit constants and registration
- `src/uikit/` — UIKit implementation fragments
- `src/shared/` — platform-neutral Lua errors, state ownership, timers,
  HTTP, and JSON
- `lua/embedded/AppKit.lua` / `UIKit.lua` — public declarative wrappers

Do not compile fragments independently. Each platform root includes its
fragments into one translation unit so static keys, Lua state, and callback
types remain shared. The Makefile discovers fragment dependencies with `find`.

## Choose Lua wrapper or native bridge

Try the generic native surface before adding C:

- `bridge._create("NativeClass")` for controls with a usable default
  initializer;
- userdata property access for KVC-compatible values;
- `bridge._perform(view, "selectorName", optionalArgument)` for ordinary
  selectors;
- `bridge._callback(view, fn)` for target/action controls;
- `applyLayout(view, props)` for standard layout modifiers.

For example, a basic AppKit `SearchField` should first be attempted entirely in
`lua/embedded/AppKit.lua` with `_create("NSSearchField")`, KVC properties,
`_callback`, and `sizeToFit`. Add a dedicated `bridge_search_field` only if a
required initializer, delegate protocol, event contract, ownership rule, or
non-KVC value cannot be represented correctly by the generic bridge.

## Implement a bridge change

1. Prove the generic path is insufficient before adding a native bridge
   function. Record the missing native capability in a concise code comment.
2. Put platform-neutral behavior in `src/shared/`; keep AppKit/UIKit types in
   their platform folder.
3. Add visual/layout constants to the platform root, never inline magic
   geometry.
4. Create a real native control and expose it as bridge-compatible userdata.
   Balance `CFBridgingRetain` with the userdata `__gc` release path.
5. Store per-object state with associated objects when possible. Avoid new
   global maps.
6. Keep Lua registry refs tied to the correct state. Resolve coroutine owners
   with `owner_for_state`; never restore raw `lua_State*` lookup tables or the
   deleted `bridge_main` workaround.
7. Register the native function in the platform root's `bridge_lib`.
8. Add or update the public wrapper in the corresponding embedded Lua module.
   Preserve established public names unless performing an intentional
   migration.
9. Add regression coverage before declaring the change complete.

When a feature requires state-dependent structural reevaluation, stop adding
feature-specific native subtree mutation. Revisit the retained-description and
reconciliation boundary documented in `docs/PROJECT_REFERENCE.md`.

## Verify

Read [references/testing.md](references/testing.md) whenever native behavior,
module registration, examples, or test infrastructure changes.

At minimum:

```sh
make test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make uikit
git diff --check
```

Use `xcode-select -p` and `xcrun --sdk iphonesimulator --show-sdk-path` before
assuming the UIKit SDK is unavailable. Setting `DEVELOPER_DIR` for one command
does not change system configuration.

Headless tests prove construction, properties, layout contracts, and data
mutation without showing windows. They do not replace required screenshot,
resize, state, accessibility, light, and dark visual QA for UI changes.
