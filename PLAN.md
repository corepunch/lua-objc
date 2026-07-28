# Plan: Proper Lua-ObjC Method Binding

## Problem

All per-object operations are flat functions on the `bridge` module:

```lua
bridge._textViewSetWrapMode(document.textView, wordWrapEnabled)
bridge._tabAdd(ntv, "File A.lua", contentA)
bridge._tableSetSelection(list, fn)
```

The goal is natural ObjC-style method calls directly on the object:

```lua
document.textView:setWrapMode(wordWrapEnabled)
ntv:addTab("File A.lua", contentA)
list:onRowSelect(fn)       -- already works today
```

## How It Works Today (and Why It's Easy to Extend)

Every ObjC object returned to Lua is a `userdata` with one of three metatables
(`nsview`, `nswindow`, `nsobject`). All three share the same `__index` handler:
`nsview_index` in `src/appkit/runtime.m`.

`TableMethods[]` in that file is the proof-of-concept: it already dispatches
`list:addRow(…)`, `list:clearRows()`, `list:onRowSelect(fn)` by detecting the
`kTableSourceKey` associated object and returning the right `lua_CFunction`.

The plan extends this exact mechanism to every remaining object type.

## Design: `<method_group>` in bridge.xml

Add a new XML element. The generator produces:

1. A `static MethodEntry XxxMethods[]` array in `src/appkit/generated/bridge_methods.m`
2. A dispatch block — `#if defined(GEN_METHODS_INDEX)` — that `nsview_index`
   `#include`s, just like `bridge_props.m` is included today.

```xml
<method_group name="text_view" detect="kTextViewSourceKey">
    <method name="setText"     src="editor.m"/>
    <method name="getText"     src="editor.m"/>
    <method name="setLanguage" src="editor.m"/>
    <method name="setWrapMode" src="editor.m"/>
    <method name="onChange"    src="editor.m"/>
</method_group>

<method_group name="tab_view" detect_class="NSTabView">
    <method name="addTab"    src="tabview.m"/>
    <method name="removeTab" src="tabview.m"/>
    <method name="selectTab" src="tabview.m"/>
    <method name="tabCount"  src="tabview.m"/>
    <method name="onChange"  src="tabview.m"/>
</method_group>
```

Two detection strategies (either on a group):
- `detect="kSomeKey"` — checks `objc_getAssociatedObject(obj, &kKeys[kSomeKey])`
- `detect_class="NSFoo"` — checks `[obj isKindOfClass:[NSFoo class]]`

## Generated Code Shape

### bridge_methods.m

```c
/* --- method dispatch arrays --- */
/* #include this block with GEN_METHODS_ARRAYS defined */
#if defined(GEN_METHODS_ARRAYS)
static MethodEntry TextViewMethods[] = {
    {"setText",     bridge_text_view_set_text},
    {"getText",     bridge_text_view_get_text},
    {"setLanguage", bridge_text_view_set_language},
    {"setWrapMode", bridge_text_view_set_wrap_mode},
    {"onChange",    bridge_text_view_on_change},
    {NULL, NULL}
};
static MethodEntry TabViewMethods[] = {
    {"addTab",    bridge_tab_add},
    {"removeTab", bridge_tab_remove},
    {"selectTab", bridge_tab_select},
    {"tabCount",  bridge_tab_count},
    {"onChange",  bridge_tab_on_change},
    {NULL, NULL}
};
#endif /* GEN_METHODS_ARRAYS */

/* --- nsview_index dispatch blocks --- */
/* #include this block with GEN_METHODS_INDEX defined */
#if defined(GEN_METHODS_INDEX)
{
    id _sentinel = objc_getAssociatedObject(obj, &kKeys[kTextViewSourceKey]);
    if (_sentinel) {
        if (strcmp(key, "getText") == 0) { lua_pushinteger(L, 0); /* handled inline */ }
        lua_CFunction _m = lookupMethod(key, TextViewMethods);
        if (_m) { lua_pushcfunction(L, _m); return 1; }
    }
}
{
    if ([obj isKindOfClass:[NSTabView class]]) {
        lua_CFunction _m = lookupMethod(key, TabViewMethods);
        if (_m) { lua_pushcfunction(L, _m); return 1; }
    }
}
#endif /* GEN_METHODS_INDEX */
```

### runtime.m changes

```c
// After the existing forward declarations, before nsview_index:
#define GEN_METHODS_ARRAYS
#include "generated/bridge_methods.m"
#undef GEN_METHODS_ARRAYS

static int nsview_index(lua_State *L) {
    // ... existing layout prop block ...

#define GEN_METHODS_INDEX
#include "generated/bridge_methods.m"
#undef GEN_METHODS_INDEX

    // ... existing KVC fallthrough + TableMethods block ...
}
```

## Sentinel for Text Views

Text views don't currently have a sentinel associated object — they're identified
by `[obj isKindOfClass:[NSScrollView class]]`. We add:

- `kTextViewSourceKey` to the `kKeys` enum in `main.m`
- `objc_setAssociatedObject(sv, &kKeys[kTextViewSourceKey], @YES, …)` in
  `bridge_text_view()` in `editor.m`

This makes detection cheap and consistent with the table/outline pattern.

## C Function Renames

The existing bridge functions keep their names — only the Lua registration entry
(in `bridge_lib[]`) changes. `bridge_tab_add` continues to be the C function
backing both the old `bridge._tabAdd(ntv, …)` and the new `ntv:addTab(…)`.
The old `bridge_lib[]` entries are removed once all Lua call sites are migrated.

## Migration of Lua Call Sites

Files to update (bridge._ → obj:method()):

| File | Calls to migrate |
|---|---|
| `examples/ide/plugins/source.lua` | `_textView`, `_textViewSet*`, `_textViewOnChange`, `_timerAfter`, `_watchFile`, `_toggleSidebar` |
| `examples/ide/plugins/text_editor.lua` | all `bridge._textView*` calls |
| `lua/embedded/AppKit.lua` | `bridge._tabAdd/Remove/Select/Count/OnChange`, `bridge._perform` calls that have method equivalents |
| `tests/bridge.test.lua` | text view tests |

`bridge._timerAfter` and `bridge._watchFile` are not object methods — they stay
as module-level functions (they don't take a view as first arg in the method sense).
`bridge._toggleSidebar(win)` becomes `win:toggleSidebar()` — added as a window
method group.

## What Stays the Same

- Memory management: `CFBridgingRetain` / `__gc` / `CFRelease`. Correct, no change.
- KVC fallthrough in `__newindex` / `__index` for simple properties.
- The `bridge` module name and all constructors (`bridge._textView()`, etc.) —
  factories stay on the module; methods move to the object.
- `TableMethods[]` and its dispatch — already correct, left as-is.
- UIKit side — out of scope for this plan.

## Steps

1. **Write PLAN.md** ✓
2. **Extend `gen_bridge.py`** — parse `<method_group>`, emit `bridge_methods.m`
3. **Add `<method_group>` entries to `bridge.xml`** — text_view, tab_view, window
4. **Add `kTextViewSourceKey`** to enum + stamp in `bridge_text_view()`
5. **Run generator** — produce `src/appkit/generated/bridge_methods.m`
6. **Update `runtime.m`** — add forward decls + two `#include` blocks
7. **Migrate Lua call sites** — `source.lua`, `text_editor.lua`, `AppKit.lua`
