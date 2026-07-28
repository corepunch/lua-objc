#!/usr/bin/env python3
"""
gen_bridge.py — generate Lua bridge boilerplate from an XML config file.

Usage:
    python3 tools/gen_bridge.py                           # AppKit (default)
    python3 tools/gen_bridge.py --xml tools/uikit_bridge.xml --out src/uikit/generated

Outputs (in --out dir):
    bridge_funcs.m   — generated bridge_xxx() C functions
    bridge_props.m   — INDEX_xxx / NEWINDEX_xxx macro calls for nsview_index/newindex
    bridge_lib.inc   — luaL_Reg entries for bridge_lib[]

Key-reference style (set via <bridge key_style="…"> in the XML):
    "enum"   (default) — &kKeys[kFooKey]   (AppKit: enum + char array)
    "direct"           — &kFooKey          (UIKit:  individual static char vars)

Callback target style (set via <bridge callback_add_target="…">):
    "property"  (default) — obj.target = X; obj.action = @selector(Y);
    "addTarget" — [obj addTarget:X action:@selector(Y) forControlEvents:Z];
    The forControlEvents value comes from the <callback> element's event="" attribute.
"""

import argparse
import os
import sys
import textwrap
import xml.etree.ElementTree as ET


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_header(xml_path):
    return f"""\
/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml {xml_path}
 * Source:           {xml_path}
 */
"""


def c_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def key_ref(key, style):
    """
    Return the key expression to pass to INDEX_xxx / NEWINDEX_xxx macros and
    to objc_setAssociatedObject / objc_getAssociatedObject.

    "enum"   — AppKit: macros take just the enum name (kFooKey); the macro
               body itself does &kKeys[kvar].  objc_*AssociatedObject calls
               also need the full address, so callers that go to those calls
               directly must use key_ref_addr() instead.
    "direct" — UIKit: bare static char, so always &kFooKey.
    """
    if style == "direct":
        return f"&{key}"
    # For the INDEX_xxx / NEWINDEX_xxx macros the second arg is the bare enum
    # name; the macro expands it to &kKeys[kvar] internally.
    return key


def key_ref_addr(key, style):
    """Full &-address for use in objc_setAssociatedObject / objc_getAssociatedObject."""
    if style == "direct":
        return f"&{key}"
    return f"&kKeys[{key}]"


# ---------------------------------------------------------------------------
# Properties  →  bridge_props.m
# ---------------------------------------------------------------------------

def gen_props(props_el, key_style, xml_path):
    index_lines = []
    newindex_lines = []

    for prop in props_el.findall("prop"):
        name  = prop.get("name")
        key   = prop.get("key")
        typ   = prop.get("type")
        dflt  = prop.get("default", "")
        clamp = prop.get("clamp", "")
        kref  = key_ref(key, key_style)

        if typ == "number":
            index_lines.append(f'INDEX_NUMBER({c_str(name)}, {kref}, {dflt});')
            if clamp:
                newindex_lines.append(f'NEWINDEX_NUMBER_CLAMP({c_str(name)}, {kref}, {clamp});')
            else:
                newindex_lines.append(f'NEWINDEX_NUMBER({c_str(name)}, {kref});')
        elif typ == "number?":
            index_lines.append(f'INDEX_NUMBER_OR_NIL({c_str(name)}, {kref});')
            if clamp:
                newindex_lines.append(f'NEWINDEX_NILABLE_NUMBER_CLAMP({c_str(name)}, {kref}, {clamp});')
            else:
                newindex_lines.append(f'NEWINDEX_NILABLE_NUMBER({c_str(name)}, {kref});')
        elif typ == "bool":
            index_lines.append(f'INDEX_BOOL({c_str(name)}, {kref});')
            newindex_lines.append(f'NEWINDEX_BOOL({c_str(name)}, {kref});')
        elif typ == "string":
            index_lines.append(f'INDEX_STRING({c_str(name)}, {kref}, {c_str(dflt)});')
            newindex_lines.append(f'NEWINDEX_STRING({c_str(name)}, {kref});')
        else:
            print(f"WARNING: unknown prop type '{typ}' for '{name}'", file=sys.stderr)

    out = [make_header(xml_path)]
    out.append("/* --- nsview_index property lookups --- */")
    out.append("/* #include this block inside nsview_index, after the key check. */")
    out.append("#if defined(GEN_PROPS_INDEX)")
    out.extend(index_lines)
    out.append("#endif /* GEN_PROPS_INDEX */")
    out.append("")
    out.append("/* --- nsview_newindex property setters --- */")
    out.append("/* #include this block inside nsview_newindex, after the key check. */")
    out.append("#if defined(GEN_PROPS_NEWINDEX)")
    out.extend(newindex_lines)
    out.append("#endif /* GEN_PROPS_NEWINDEX */")
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Constructor  →  bridge_xxx() function body
# ---------------------------------------------------------------------------

def gen_constructor(el, key_style, cb_style):
    name    = el.get("name")
    returns = el.get("returns", "nsview")
    lines   = []

    lines.append(f"static int bridge_{name}(lua_State *L) {{")

    # ── Arg declarations ────────────────────────────────────────────────────
    args = el.findall("arg")
    for arg in args:
        idx      = arg.get("index")
        aname    = arg.get("name")
        typ      = arg.get("type")
        required = arg.get("required", "true") == "true"
        default  = arg.get("default", "")

        if typ == "string":
            if required:
                lines.append(f"\tconst char *{aname} = luaL_checkstring(L, {idx});")
            else:
                dflt = c_str(default) if default else '""'
                lines.append(f"\tconst char *{aname} = luaL_optstring(L, {idx}, {dflt});")
        elif typ == "number":
            if required:
                lines.append(f"\tCGFloat {aname} = (CGFloat)luaL_checknumber(L, {idx});")
            else:
                dflt = default if default else "0"
                lines.append(f"\tCGFloat {aname} = (CGFloat)luaL_optnumber(L, {idx}, {dflt});")
        elif typ == "integer":
            if required:
                lines.append(f"\tNSInteger {aname} = (NSInteger)luaL_checkinteger(L, {idx});")
            else:
                dflt = default if default else "0"
                lines.append(f"\tNSInteger {aname} = (NSInteger)luaL_optinteger(L, {idx}, {dflt});")
        elif typ == "bool":
            lines.append(f"\tBOOL {aname} = (BOOL)lua_toboolean(L, {idx});")
        elif typ in ("function", "function?"):
            lines.append(f"\tBOOL has_{aname} = !lua_isnoneornil(L, {idx});")
            lines.append(f"\tint {aname}_ref = LUA_NOREF;")
        elif typ in ("object", "view"):
            checker = "check_objc" if typ == "object" else "check_view"
            lines.append(f"\tid {aname} = {checker}(L, {idx});")
        elif typ == "table":
            lines.append(f"\tluaL_checktype(L, {idx}, LUA_TTABLE);")

    # ── Callback ref capture ─────────────────────────────────────────────────
    for arg in args:
        if arg.get("type") in ("function", "function?"):
            aname = arg.get("name")
            idx   = arg.get("index")
            req   = arg.get("required", "true") == "true"
            if req:
                lines.append(f"\tluaL_checktype(L, {idx}, LUA_TFUNCTION);")
                lines.append(f"\tlua_pushvalue(L, {idx});")
                lines.append(f"\t{aname}_ref = luaL_ref(L, LUA_REGISTRYINDEX);")
            else:
                lines.append(f"\tif (has_{aname}) {{")
                lines.append(f"\t\tluaL_checktype(L, {idx}, LUA_TFUNCTION);")
                lines.append(f"\t\tlua_pushvalue(L, {idx});")
                lines.append(f"\t\t{aname}_ref = luaL_ref(L, LUA_REGISTRYINDEX);")
                lines.append(f"\t}}")
    lines.append("")

    # ── Alloc / factory ──────────────────────────────────────────────────────
    alloc_el         = el.find("alloc")
    alloc_factory_el = el.find("alloc_factory")
    var = "obj"

    if alloc_el is not None:
        cls   = alloc_el.get("class")
        frame = alloc_el.get("frame", "NSZeroRect")
        lines.append(f"\t{cls} *{var} = [[{cls} alloc] initWithFrame:{frame}];")
    elif alloc_factory_el is not None:
        cls    = alloc_factory_el.get("class")
        method = alloc_factory_el.get("method")
        fargs  = alloc_factory_el.get("args", "")
        parts    = [p for p in method.split(":") if p]
        arg_list = [a.strip() for a in fargs.split(",")]
        if len(parts) == len(arg_list):
            interleaved = " ".join(f"{p}:{a}" for p, a in zip(parts, arg_list))
            lines.append(f"\t{cls} *{var} = [{cls} {interleaved}];")
        else:
            lines.append(f"\t{cls} *{var} = [{cls} {method}];")

    # ── Property assignments ──────────────────────────────────────────────────
    for sp in el.findall("set_prop"):
        prop     = sp.get("property")
        value    = sp.get("value", "")
        from_arg = sp.get("from_arg", "")
        if from_arg:
            lines.append(f"\t{var}.{prop} = [NSString stringWithUTF8String:{from_arg}];")
        else:
            lines.append(f"\t{var}.{prop} = {value};")

    # ── Method calls and raw statements ──────────────────────────────────────
    for cm in el.findall("call_method"):
        method = cm.get("method")
        if ":" in method:
            # method already contains the full ObjC message, e.g.
            # "setTitle:[NSString stringWithUTF8String:title] forState:UIControlStateNormal"
            lines.append(f"\t[{var} {method}];")
        else:
            lines.append(f"\t[{var} {method}];")
    for rl in el.findall("raw"):
        # <raw>arbitrary C statement; var is available as "obj"</raw>
        for line in textwrap.dedent(rl.text or "").strip().splitlines():
            lines.append(f"\t{line}")

    # ── Associated-object stamps ──────────────────────────────────────────────
    for assoc in el.findall("assoc"):
        kaddr = key_ref_addr(assoc.get("key"), key_style)
        value = assoc.get("value")
        lines.append(f"\tobjc_setAssociatedObject({var}, {kaddr}, {value}, OBJC_ASSOCIATION_RETAIN);")

    # ── Callback wiring ───────────────────────────────────────────────────────
    cb_el = el.find("callback")
    if cb_el is not None:
        arg_name = cb_el.get("arg")
        cb_key   = cb_el.get("key")
        target   = cb_el.get("target")
        action   = cb_el.get("action")
        event    = cb_el.get("event", "UIControlEventTouchUpInside")
        kaddr    = key_ref_addr(cb_key, key_style)
        lines.append(f"\tif (has_{arg_name}) {{")
        lines.append(f"\t\tobjc_setAssociatedObject({var}, {kaddr}, @({arg_name}_ref), OBJC_ASSOCIATION_RETAIN);")
        if cb_style == "addTarget":
            lines.append(f"\t\t[{var} addTarget:{target} action:@selector({action}) forControlEvents:{event}];")
        else:
            lines.append(f"\t\t{var}.target = {target};")
            lines.append(f"\t\t{var}.action = @selector({action});")
        lines.append(f"\t}}")

    lines.append(f"\tpush_objc(L, {var}, {c_str(returns)});")
    lines.append("\treturn 1;")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Callback setter  →  bridge_xxx() function body
# ---------------------------------------------------------------------------

def gen_callback_setter(el, key_style):
    name = el.get("name")
    lines = []

    guard_el  = el.find("guard")
    store_el  = el.find("store")
    side_set  = el.find("side_effect_set")
    side_clr  = el.find("side_effect_clear")

    guard_type = guard_el.get("type") if guard_el is not None else None
    guard_key  = guard_el.get("key")  if guard_el is not None else None
    guard_msg  = guard_el.get("msg")  if guard_el is not None else "invalid view"
    store_key  = store_el.get("key")  if store_el is not None else None
    store_on   = store_el.get("on")   if store_el is not None else "obj"

    lines.append(f"static int bridge_{name}(lua_State *L) {{")
    lines.append("\tid obj = check_objc(L, 1);")

    if guard_el is not None:
        gkaddr = key_ref_addr(guard_key, key_style)
        if guard_type and guard_type != "id":
            lines.append(f"\t{guard_type} *src = objc_getAssociatedObject(obj, {gkaddr});")
            lines.append(f"\tif (!src) return luaL_error(L, {c_str(guard_msg)});")
        else:
            lines.append(f"\tid src = objc_getAssociatedObject(obj, {gkaddr});")
            lines.append(f"\tif (!src) return luaL_error(L, {c_str(guard_msg)});")

    skaddr = key_ref_addr(store_key, key_style)
    lines.append("\tif (lua_isnoneornil(L, 2)) {")
    if side_clr is not None:
        for line in textwrap.dedent(side_clr.text or "").strip().splitlines():
            lines.append(f"\t\t{line}")
    lines.append(f"\t\tobjc_setAssociatedObject({store_on}, {skaddr}, nil, OBJC_ASSOCIATION_ASSIGN);")
    lines.append("\t\treturn 0;")
    lines.append("\t}")
    lines.append("\tluaL_checktype(L, 2, LUA_TFUNCTION);")
    lines.append("\tlua_pushvalue(L, 2);")
    lines.append("\tint ref = luaL_ref(L, LUA_REGISTRYINDEX);")
    if side_set is not None:
        for line in textwrap.dedent(side_set.text or "").strip().splitlines():
            lines.append(f"\t{line}")
    lines.append(f"\tobjc_setAssociatedObject({store_on}, {skaddr}, @(ref), OBJC_ASSOCIATION_RETAIN);")
    lines.append("\treturn 0;")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Class bindings  →  bridge_class_methods.m
# ---------------------------------------------------------------------------
#
# <class name="NSTabView" lua_name="TabView" detect_class="NSTabView">
#     <method name="addTab" impl="true">
#         <arg name="title"   type="string"/>
#         <arg name="content" type="nsview"/>
#     </method>
#     <method name="tabCount" impl="true"/>
#     <method name="selectTab">
#         <arg name="index" type="integer"/>
#         <objc>
#             if (index >= 0 && index < (NSInteger)self.numberOfTabViewItems)
#                 [self selectTabViewItemAtIndex:index];
#         </objc>
#     </method>
# </class>
#
# When impl="true" the wrapper calls bridge_ClassName_methodName_impl(L, self, ...).
# When a method body is provided via <objc> the generator emits it directly;
# otherwise it emits a delegate-to-_impl wrapper.

_OBJC_CLASS_TO_C_TYPE = {
    "NSTabView":    "NSTabView *",
    "NSScrollView": "NSScrollView *",
    "NSTextView":   "NSTextView *",
    "NSTextField":  "NSTextField *",
    "NSWindow":     "NSWindow *",
    "NSView":       "NSView *",
    "NSPanel":      "NSPanel *",
}

_LUA_TO_C_ARG_CHECK = {
    "string":    lambda idx, name, opt, dflt: f"\tconst char *{name} = {'luaL_optstring' if opt else 'luaL_checkstring'}(L, {idx}{', ' + dflt if opt and dflt else ''});",
    "number":    lambda idx, name, opt, dflt: f"\tCGFloat {name} = (CGFloat){'luaL_optnumber' if opt else 'luaL_checknumber'}(L, {idx}{', ' + dflt if opt and dflt else ''});",
    "integer":   lambda idx, name, opt, dflt: f"\tNSInteger {name} = (NSInteger){'luaL_optinteger' if opt else 'luaL_checkinteger'}(L, {idx}{', ' + (dflt + 'L') if opt and dflt else ''});",
    "bool":      lambda idx, name, opt, dflt: f"\tBOOL {name} = (BOOL)lua_toboolean(L, {idx});",
    "nsview":    lambda idx, name, opt, dflt: f"\tNSView *{name} = check_view(L, {idx});",
    "nsobject":  lambda idx, name, opt, dflt: f"\tid {name} = check_objc(L, {idx});",
    "nswindow":  lambda idx, name, opt, dflt: f"\tNSWindow *{name} = lua_objc_check_object(L, {idx}, [NSWindow class], \"NSWindow\");",
    "function":  lambda idx, name, opt, dflt: f"\tluaL_checktype(L, {idx}, LUA_TFUNCTION);\n\tlua_pushvalue(L, {idx});\n\tint {name} = luaL_ref(L, LUA_REGISTRYINDEX);",
    "function?": lambda idx, name, opt, dflt: f"\tBOOL has_{name} = !lua_isnoneornil(L, {idx});\n\tint {name} = LUA_NOREF;\n\tif (has_{name}) {{\n\t\tluaL_checktype(L, {idx}, LUA_TFUNCTION);\n\t\tlua_pushvalue(L, {idx});\n\t\t{name} = luaL_ref(L, LUA_REGISTRYINDEX);\n\t}}",
    "table":     lambda idx, name, opt, dflt: f"\tluaL_checktype(L, {idx}, LUA_TTABLE);",
}

_LUA_TO_C_IMPL_TYPE = {
    "string":    "const char *",
    "number":    "CGFloat",
    "integer":   "NSInteger",
    "bool":      "BOOL",
    "nsview":    "NSView *",
    "nsobject":  "id",
    "nswindow":  "NSWindow *",
    "function":  "int",
    "function?": "int",
    "table":     "int",
}


def gen_class_bindings(classes, key_style, xml_path):
    """Generate bridge_class_methods.m from <class> elements.

    Sections:
      GEN_CLASS_FORWARDS  — forward decls for _impl functions
      GEN_CLASS_WRAPPERS  — auto-generated wrapper functions
      GEN_CLASS_ARRAYS    — MethodEntry[] dispatch tables
      GEN_CLASS_INDEX     — nsview_index dispatch blocks
    """
    fwd_lines = []
    wrapper_lines = []
    array_lines = []
    index_lines = []

    for cls in classes:
        cls_name   = cls.get("name")           # "NSTabView"
        lua_name   = cls.get("lua_name")       # "TabView"
        detect_key = cls.get("detect")
        detect_cls = cls.get("detect_class")
        array_name = lua_name + "Methods"

        c_self_type = _OBJC_CLASS_TO_C_TYPE.get(cls_name, "id")
        self_class_expr = f"[{cls_name} class]"

        methods = cls.findall("method")

        # --- per-method generation ---
        for m in methods:
            mname = m.get("name")
            has_impl = m.get("impl", "false") == "true"
            wrapper_func = f"bridge_{cls_name}_{mname}"
            impl_func = f"bridge_{cls_name}_{mname}_impl"
            body_el = m.find("objc")
            args = m.findall("arg")

            # --- Forward declaration for _impl ---
            if has_impl:
                arg_sig = ", ".join(
                    _LUA_TO_C_IMPL_TYPE.get(a.get("type"), "id") + " " + a.get("name")
                    for a in args
                )
                fwd_lines.append(f"static int {impl_func}(lua_State *L, {c_self_type}self{', ' + arg_sig if arg_sig else ''});")

            # --- Wrapper function ---
            wrapper_lines.append(f"static int {wrapper_func}(lua_State *L) {{")
            wrapper_lines.append(f"\tid _obj = lua_objc_check_object(L, 1, {self_class_expr}, {c_str(lua_name)});")
            wrapper_lines.append(f"\t{c_self_type}self = ({c_self_type})_obj;")

            arg_names = []
            for a in args:
                aname = a.get("name")
                atyp  = a.get("type", "nsobject")
                idx   = str(len(arg_names) + 2)
                opt   = atyp.endswith("?")
                dflt  = a.get("default", "")
                check_fn = _LUA_TO_C_ARG_CHECK.get(atyp)
                if check_fn:
                    wrapper_lines.append(check_fn(idx, aname, opt, c_str(dflt) if opt and dflt else dflt))
                else:
                    wrapper_lines.append(f"\t/* unknown type: {atyp} */")
                arg_names.append(aname)

            if body_el is not None:
                wrapper_lines.append(f"\t{{")
                for line in textwrap.dedent(body_el.text or "").strip().splitlines():
                    wrapper_lines.append(f"\t\t{line}")
                wrapper_lines.append(f"\t}}")
                wrapper_lines.append(f"\treturn 0;")
            elif has_impl:
                call_args = ", ".join(["L", "self"] + arg_names)
                wrapper_lines.append(f"\treturn {impl_func}({call_args});")
            else:
                wrapper_lines.append(f"\treturn 0;")

            wrapper_lines.append("}")
            wrapper_lines.append("")

        # --- MethodEntry array ---
        array_lines.append(f"static MethodEntry {array_name}[] = {{")
        for m in methods:
            mname = m.get("name")
            wrapper_func = f"bridge_{cls_name}_{mname}"
            array_lines.append(f'\t{{{c_str(mname)},\t{wrapper_func}}},')
        array_lines.append(f'\t{{NULL, NULL}}')
        array_lines.append("};")
        array_lines.append("")

        # --- Dispatch block ---
        index_lines.append("{")
        if detect_key:
            kaddr = key_ref_addr(detect_key, key_style)
            index_lines.append(f"\tid _sentinel_{cls_name.lower()} = objc_getAssociatedObject(obj, {kaddr});")
            index_lines.append(f"\tif (_sentinel_{cls_name.lower()}) {{")
        elif detect_cls:
            index_lines.append(f"\tif ([obj isKindOfClass:[{detect_cls} class]]) {{")
        else:
            index_lines.append("\tif (YES) {")
        index_lines.append(f"\t\tlua_CFunction _m = lookupMethod(key, {array_name});")
        index_lines.append(f"\t\tif (_m) {{ lua_pushcfunction(L, _m); return 1; }}")
        index_lines.append("\t}")
        index_lines.append("}")
        index_lines.append("")

    out = [make_header(xml_path)]

    out.append("/* --- _impl forward declarations --- */")
    out.append("#if defined(GEN_CLASS_FORWARDS)")
    out.extend(fwd_lines)
    out.append("#endif /* GEN_CLASS_FORWARDS */")
    out.append("")

    out.append("/* --- Auto-generated wrapper functions --- */")
    out.append("#if defined(GEN_CLASS_WRAPPERS)")
    out.extend(wrapper_lines)
    out.append("#endif /* GEN_CLASS_WRAPPERS */")
    out.append("")

    out.append("/* --- MethodEntry dispatch arrays --- */")
    out.append("#if defined(GEN_CLASS_ARRAYS)")
    out.extend(array_lines)
    out.append("#endif /* GEN_CLASS_ARRAYS */")
    out.append("")

    out.append("/* --- nsview_index dispatch blocks --- */")
    out.append("#if defined(GEN_CLASS_INDEX)")
    out.extend(index_lines)
    out.append("#endif /* GEN_CLASS_INDEX */")
    out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Method groups  →  bridge_methods.m
# ---------------------------------------------------------------------------

def c_func_name(method_name):
    """Convert camelCase Lua method name to bridge_xxx_yyy C function name.

    setText      → bridge_text_view_set_text   (caller prefixes group)
    We don't prefix here — caller passes the group prefix separately.
    """
    import re
    # Insert underscore before each uppercase letter, then lowercase
    s = re.sub(r'([A-Z])', r'_\1', method_name).lower()
    return s


def gen_methods(method_groups, key_style, xml_path):
    """Generate bridge_methods.m with MethodEntry arrays and __index dispatch blocks."""

    arrays_lines = []   # inside GEN_METHODS_ARRAYS guard
    index_lines  = []   # inside GEN_METHODS_INDEX guard
    forward_lines = []  # inside GEN_METHODS_FORWARDS guard

    for mg in method_groups:
        group_name  = mg.get("name")          # e.g. "text_view"
        detect_key  = mg.get("detect")        # e.g. "kTextViewSourceKey"
        detect_class = mg.get("detect_class") # e.g. "NSTabView"
        array_name  = "".join(w.capitalize() for w in group_name.split("_")) + "Methods"
        # e.g. "text_view" → "TextViewMethods"

        methods = mg.findall("method")

        # --- Forward declarations ---
        for m in methods:
            mname = m.get("name")
            cfunc = "bridge_" + group_name + "_method_" + c_func_name(mname).lstrip("_")
            # actual C name is specified via c_func attr, or derived
            cfunc = m.get("c_func", "bridge_" + group_name.replace("_", "_") + "_" + c_func_name(mname).lstrip("_"))
            forward_lines.append(f"static int {cfunc}(lua_State *L);")

        # --- MethodEntry array ---
        arrays_lines.append(f"static MethodEntry {array_name}[] = {{")
        for m in methods:
            mname = m.get("name")
            cfunc = m.get("c_func", "bridge_" + group_name + "_" + c_func_name(mname).lstrip("_"))
            arrays_lines.append(f'\t{{{c_str(mname)},\t{cfunc}}},')
        arrays_lines.append(f'\t{{NULL, NULL}}')
        arrays_lines.append("};")
        arrays_lines.append("")

        # --- Dispatch block in nsview_index ---
        index_lines.append("{")
        if detect_key:
            kaddr = key_ref_addr(detect_key, key_style)
            index_lines.append(f"\tid _sentinel_{group_name} = objc_getAssociatedObject(obj, {kaddr});")
            index_lines.append(f"\tif (_sentinel_{group_name}) {{")
        elif detect_class:
            index_lines.append(f"\tif ([obj isKindOfClass:[{detect_class} class]]) {{")
        else:
            index_lines.append("\tif (YES) {")

        index_lines.append(f"\t\tlua_CFunction _m = lookupMethod(key, {array_name});")
        index_lines.append(f"\t\tif (_m) {{ lua_pushcfunction(L, _m); return 1; }}")
        index_lines.append("\t}")
        index_lines.append("}")
        index_lines.append("")

    out = [make_header(xml_path)]

    out.append("/* --- method C function forward declarations --- */")
    out.append("/* #include with GEN_METHODS_FORWARDS defined, before runtime.m method tables */")
    out.append("#if defined(GEN_METHODS_FORWARDS)")
    out.extend(forward_lines)
    out.append("#endif /* GEN_METHODS_FORWARDS */")
    out.append("")

    out.append("/* --- MethodEntry arrays for each method group --- */")
    out.append("/* #include with GEN_METHODS_ARRAYS defined, before nsview_index */")
    out.append("#if defined(GEN_METHODS_ARRAYS)")
    out.extend(arrays_lines)
    out.append("#endif /* GEN_METHODS_ARRAYS */")
    out.append("")

    out.append("/* --- nsview_index dispatch blocks --- */")
    out.append("/* #include with GEN_METHODS_INDEX defined, inside nsview_index body */")
    out.append("#if defined(GEN_METHODS_INDEX)")
    out.extend(index_lines)
    out.append("#endif /* GEN_METHODS_INDEX */")
    out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# bridge_lib.inc
# ---------------------------------------------------------------------------

def gen_lib_entries(root, xml_path):
    entries = []
    for el in root:
        tag      = el.tag
        name     = el.get("name")
        lua_name = el.get("lua_name")
        if tag in ("constructor", "callback_setter", "manual_entry"):
            entries.append((lua_name, f"bridge_{name}"))

    lines = [make_header(xml_path)]
    lines.append("/* luaL_Reg entries — #include inside bridge_lib[] initialiser */")
    lines.append("#if defined(GEN_BRIDGE_LIB)")
    for lua_n, c_n in entries:
        lines.append(f'\t{{{c_str(lua_n)},\t{c_n}}},')
    lines.append("#endif /* GEN_BRIDGE_LIB */")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate Lua bridge boilerplate from XML.")
    parser.add_argument("--xml", default="tools/bridge.xml")
    parser.add_argument("--out", default="src/appkit/generated")
    args = parser.parse_args()

    tree = ET.parse(args.xml)
    root = tree.getroot()

    key_style = root.get("key_style", "enum")    # "enum" | "direct"
    cb_style  = root.get("callback_style", "property")  # "property" | "addTarget"

    os.makedirs(args.out, exist_ok=True)

    # bridge_props.m
    props_el = root.find("properties")
    if props_el is not None:
        with open(os.path.join(args.out, "bridge_props.m"), "w") as f:
            f.write(gen_props(props_el, key_style, args.xml))
        print(f"  wrote {args.out}/bridge_props.m")

    # bridge_funcs.m
    hdr = make_header(args.xml)
    funcs = [hdr, "/* Generated bridge_xxx() functions */", ""]
    for el in root:
        if el.tag == "constructor":
            funcs.append(gen_constructor(el, key_style, cb_style))
        elif el.tag == "callback_setter":
            funcs.append(gen_callback_setter(el, key_style))

    with open(os.path.join(args.out, "bridge_funcs.m"), "w") as f:
        f.write("\n".join(funcs))
    print(f"  wrote {args.out}/bridge_funcs.m")

    # bridge_lib.inc
    with open(os.path.join(args.out, "bridge_lib.inc"), "w") as f:
        f.write(gen_lib_entries(root, args.xml))
    print(f"  wrote {args.out}/bridge_lib.inc")

    # bridge_methods.m  (only if any <method_group> elements exist)
    method_groups = root.findall("method_group")
    if method_groups:
        with open(os.path.join(args.out, "bridge_methods.m"), "w") as f:
            f.write(gen_methods(method_groups, key_style, args.xml))
        print(f"  wrote {args.out}/bridge_methods.m")

    # bridge_class_methods.m  (only if any <class> elements exist)
    classes = root.findall("class")
    if classes:
        with open(os.path.join(args.out, "bridge_class_methods.m"), "w") as f:
            f.write(gen_class_bindings(classes, key_style, args.xml))
        print(f"  wrote {args.out}/bridge_class_methods.m")

    print("Done.")


if __name__ == "__main__":
    main()
