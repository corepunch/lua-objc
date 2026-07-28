#!/usr/bin/env python3
"""
gen_bridge.py — generate Lua bridge boilerplate from an XML config file.

Usage:
    python3 tools/gen_bridge.py                           # AppKit (default)
    python3 tools/gen_bridge.py --xml tools/UIKit.xml --out src/uikit/generated

Outputs (in --out dir):
    bridge_structs.m — generated native value userdata and registration
    bridge_funcs.m   — generated bridge_xxx() C functions
    bridge_props.m   — class-scoped property access for nsview_index/newindex
    bridge_lib.inc   — luaL_Reg entries for bridge_lib[]
    bridge_class_methods.m — typed wrappers, method tables, and class dispatch

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
import re
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

def class_guard(cls):
    detect_key = cls.get("detect")
    detect_cls = cls.get("detect_class")
    if detect_key:
        return ("associated",
                detect_key,
                f"objc_getAssociatedObject(obj, {{key}})")
    if detect_cls:
        return ("class", detect_cls, f"[obj isKindOfClass:[{detect_cls} class]]")
    return ("always", "", "YES")


def gen_props(classes, structs, key_style, xml_path):
    index_lines = []
    newindex_lines = []

    for cls in classes:
        props_el = cls.find("properties")
        if props_el is None:
            continue
        guard_kind, guard_value, guard_expr = class_guard(cls)
        if guard_kind == "associated":
            guard_expr = guard_expr.format(
                key=key_ref_addr(guard_value, key_style))
        index_lines.append(f"if ({guard_expr}) {{")
        newindex_lines.append(f"if ({guard_expr}) {{")

        for prop in props_el.findall("property"):
            name = prop.get("name")
            key = prop.get("key")
            typ = prop.get("type")
            dflt = prop.get("default", "")
            clamp = prop.get("clamp", "")
            native = prop.get("native")
            getter = prop.get("getter")
            readonly = prop.get("readonly", "false") == "true"
            if typ in structs:
                if not native and not getter:
                    raise ValueError(
                        f"{cls.get('name')}.{name}: struct property requires "
                        "native= or getter=")
                cast = f"(({cls.get('name')} *)obj)"
                value_expr = getter or f"{cast}.{native}"
                index_lines.extend([
                    f'\tif (strcmp(key, {c_str(name)}) == 0) {{',
                    f'\t\tpush_{typ}(L, {value_expr});',
                    '\t\treturn 1;',
                    '\t}',
                ])
                if not readonly:
                    newindex_lines.extend([
                        f'\tif (strcmp(key, {c_str(name)}) == 0) {{',
                        f'\t\t{cast}.{native} = *check_{typ}(L, 3);',
                        '\t\treturn 0;',
                        '\t}',
                    ])
                continue
            if not key:
                raise ValueError(
                    f"{cls.get('name')}.{name}: associated property requires key")
            kref = key_ref(key, key_style)

            if typ == "number":
                index_lines.append(f'\tINDEX_NUMBER({c_str(name)}, {kref}, {dflt});')
                if clamp:
                    newindex_lines.append(f'\tNEWINDEX_NUMBER_CLAMP({c_str(name)}, {kref}, {clamp});')
                else:
                    newindex_lines.append(f'\tNEWINDEX_NUMBER({c_str(name)}, {kref});')
            elif typ == "number?":
                index_lines.append(f'\tINDEX_NUMBER_OR_NIL({c_str(name)}, {kref});')
                if clamp:
                    newindex_lines.append(f'\tNEWINDEX_NILABLE_NUMBER_CLAMP({c_str(name)}, {kref}, {clamp});')
                else:
                    newindex_lines.append(f'\tNEWINDEX_NILABLE_NUMBER({c_str(name)}, {kref});')
            elif typ == "bool":
                index_lines.append(f'\tINDEX_BOOL({c_str(name)}, {kref});')
                newindex_lines.append(f'\tNEWINDEX_BOOL({c_str(name)}, {kref});')
            elif typ == "string":
                index_lines.append(f'\tINDEX_STRING({c_str(name)}, {kref}, {c_str(dflt)});')
                newindex_lines.append(f'\tNEWINDEX_STRING({c_str(name)}, {kref});')
            else:
                raise ValueError(
                    f"{cls.get('name')}.{name}: unknown property type {typ!r}")

        index_lines.append("}")
        newindex_lines.append("}")

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
# Native structs → bridge_structs.m
# ---------------------------------------------------------------------------

def gen_structs(structs, xml_path):
    lines = [make_header(xml_path), "#if defined(GEN_STRUCT_HELPERS)"]
    for struct in structs.values():
        name = struct.get("name")
        fields = struct.findall("field")
        meta = f"lua_objc.struct.{name}"
        lines.extend([
            f"static {name} *check_{name}(lua_State *L, int idx) {{",
            f"\treturn ({name} *)luaL_checkudata(L, idx, {c_str(meta)});",
            "}",
            "",
            f"static void push_{name}(lua_State *L, {name} value) {{",
            f"\t{name} *box = ({name} *)lua_newuserdata(L, sizeof({name}));",
            "\t*box = value;",
            f"\tluaL_setmetatable(L, {c_str(meta)});",
            "}",
            "",
            f"static int index_{name}(lua_State *L) {{",
            f"\t{name} *value = check_{name}(L, 1);",
            "\tconst char *key = luaL_checkstring(L, 2);",
        ])
        for field in fields:
            fname = field.get("name")
            ftype = field.get("type")
            lines.append(f"\tif (strcmp(key, {c_str(fname)}) == 0) {{")
            if ftype == "number":
                lines.append(f"\t\tlua_pushnumber(L, value->{fname});")
            elif ftype in structs:
                lines.append(f"\t\tpush_{ftype}(L, value->{fname});")
            else:
                raise ValueError(f"{name}.{fname}: unknown struct field type {ftype!r}")
            lines.extend(["\t\treturn 1;", "\t}"])
        lines.extend(["\tlua_pushnil(L);", "\treturn 1;", "}", ""])
        lines.extend([
            f"static int newindex_{name}(lua_State *L) {{",
            f"\t{name} *value = check_{name}(L, 1);",
            "\tconst char *key = luaL_checkstring(L, 2);",
        ])
        for field in fields:
            fname = field.get("name")
            ftype = field.get("type")
            lines.append(f"\tif (strcmp(key, {c_str(fname)}) == 0) {{")
            if ftype == "number":
                lines.append(f"\t\tvalue->{fname} = (CGFloat)luaL_checknumber(L, 3);")
            else:
                lines.append(f"\t\tvalue->{fname} = *check_{ftype}(L, 3);")
            lines.extend(["\t\treturn 0;", "\t}"])
        lines.extend([
            f"\treturn luaL_error(L, \"unknown {name} field: %s\", key);",
            "}",
            "",
            f"static int bridge_{name}(lua_State *L) {{",
            f"\t{name} value = {{0}};",
            "\tif (lua_istable(L, 1)) {",
        ])
        for field in fields:
            fname = field.get("name")
            ftype = field.get("type")
            lines.append(f"\t\tlua_getfield(L, 1, {c_str(fname)});")
            if ftype == "number":
                lines.append(f"\t\tvalue.{fname} = (CGFloat)luaL_checknumber(L, -1);")
            else:
                lines.append(f"\t\tvalue.{fname} = *check_{ftype}(L, -1);")
            lines.append("\t\tlua_pop(L, 1);")
        lines.append("\t} else {")
        for idx, field in enumerate(fields, 1):
            fname = field.get("name")
            ftype = field.get("type")
            if ftype == "number":
                lines.append(f"\t\tvalue.{fname} = (CGFloat)luaL_checknumber(L, {idx});")
            else:
                lines.append(f"\t\tvalue.{fname} = *check_{ftype}(L, {idx});")
        lines.extend([
            "\t}",
            f"\tpush_{name}(L, value);",
            "\treturn 1;",
            "}",
            "",
            f"static void register_{name}(lua_State *L) {{",
            f"\tluaL_newmetatable(L, {c_str(meta)});",
            f"\tlua_pushcfunction(L, index_{name});",
            "\tlua_setfield(L, -2, \"__index\");",
            f"\tlua_pushcfunction(L, newindex_{name});",
            "\tlua_setfield(L, -2, \"__newindex\");",
            "\tlua_pop(L, 1);",
            "}",
            "",
        ])
    lines.append("#endif /* GEN_STRUCT_HELPERS */")
    lines.append("")
    lines.append("#if defined(GEN_STRUCT_REGISTER)")
    for name in structs:
        lines.append(f"\tregister_{name}(L);")
    lines.append("#endif /* GEN_STRUCT_REGISTER */")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Constructor  →  bridge_xxx() function body
# ---------------------------------------------------------------------------

def gen_constructor(el, key_style, cb_style, function_name=None):
    name    = el.get("name")
    returns = el.get("returns", "nsview")
    lines   = []

    function_name = function_name or f"bridge_{name}"
    lines.append(f"static int {function_name}(lua_State *L) {{")

    # ── Arg declarations ────────────────────────────────────────────────────
    args = el.findall("arg")
    for position, arg in enumerate(args, 1):
        idx      = arg.get("index", str(position))
        aname    = arg.get("name")
        typ      = arg.get("type")
        required = (arg.get("required", "true") == "true"
                    and not typ.endswith("?"))
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
    for position, arg in enumerate(args, 1):
        if arg.get("type") in ("function", "function?"):
            aname = arg.get("name")
            idx   = arg.get("index", str(position))
            req   = (arg.get("required", "true") == "true"
                     and not arg.get("type", "").endswith("?"))
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

def gen_callback_setter(el, key_style, function_name=None):
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

    function_name = function_name or f"bridge_{name}"
    lines.append(f"static int {function_name}(lua_State *L) {{")
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
    "nsview?":   lambda idx, name, opt, dflt: f"\tNSView *{name} = lua_isnoneornil(L, {idx}) ? nil : check_view(L, {idx});",
    "nsobject":  lambda idx, name, opt, dflt: f"\tid {name} = check_objc(L, {idx});",
    "nsobject?": lambda idx, name, opt, dflt: f"\tid {name} = lua_isnoneornil(L, {idx}) ? nil : check_objc(L, {idx});",
    "nswindow":  lambda idx, name, opt, dflt: f"\tNSWindow *{name} = lua_objc_check_object(L, {idx}, [NSWindow class], \"NSWindow\");",
    "function":  lambda idx, name, opt, dflt: f"\tluaL_checktype(L, {idx}, LUA_TFUNCTION);\n\tlua_pushvalue(L, {idx});\n\tint {name} = luaL_ref(L, LUA_REGISTRYINDEX);",
    "function?": lambda idx, name, opt, dflt: f"\tBOOL has_{name} = !lua_isnoneornil(L, {idx});\n\tint {name} = LUA_NOREF;\n\tif (has_{name}) {{\n\t\tluaL_checktype(L, {idx}, LUA_TFUNCTION);\n\t\tlua_pushvalue(L, {idx});\n\t\t{name} = luaL_ref(L, LUA_REGISTRYINDEX);\n\t}}",
    "table":     lambda idx, name, opt, dflt: f"\tluaL_checktype(L, {idx}, LUA_TTABLE);",
    "any":       lambda idx, name, opt, dflt: f"\t(void)lua_type(L, {idx});",
}

_LUA_TO_C_IMPL_TYPE = {
    "string":    "const char *",
    "number":    "CGFloat",
    "integer":   "NSInteger",
    "bool":      "BOOL",
    "nsview":    "NSView *",
    "nsview?":   "NSView *",
    "nsobject":  "id",
    "nswindow":  "NSWindow *",
    "function":  "int",
    "function?": "int",
    "table":     "int",
}

_OBJC_ENUM_TYPES = {
    "NSWindowTabbingMode": (
        ("automatic", "NSWindowTabbingModeAutomatic"),
        ("preferred", "NSWindowTabbingModePreferred"),
        ("disallowed", "NSWindowTabbingModeDisallowed"),
    ),
}


def snake_case(name):
    first = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", first).lower()


def objc_arg_expr(arg):
    typ = arg.get("type", "nsobject").rstrip("?")
    name = arg.get("name")
    if typ == "string":
        return f"[NSString stringWithUTF8String:{name}]"
    return name


def objc_return(lines, return_type, message):
    if return_type in (None, "void"):
        lines.append(f"\t{message};")
        lines.append("\treturn 0;")
    elif return_type == "bool":
        lines.append(f"\tlua_pushboolean(L, {message});")
        lines.append("\treturn 1;")
    elif return_type == "integer":
        lines.append(f"\tlua_pushinteger(L, (lua_Integer){message});")
        lines.append("\treturn 1;")
    elif return_type == "number":
        lines.append(f"\tlua_pushnumber(L, (lua_Number){message});")
        lines.append("\treturn 1;")
    elif return_type == "string":
        lines.append(f"\tNSString *_result = {message};")
        lines.append("\tlua_pushstring(L, _result.UTF8String);")
        lines.append("\treturn 1;")
    elif return_type in ("nsobject", "nsview", "nswindow"):
        metatable = {
            "nsobject": "nsobject",
            "nsview": "nsview",
            "nswindow": "nswindow",
        }[return_type]
        lines.append(f"\tid _result = {message};")
        lines.append(f"\tpush_objc(L, _result, {c_str(metatable)});")
        lines.append("\treturn 1;")
    else:
        raise ValueError(f"unknown method return type {return_type!r}")


def stack_arg_check(arg, idx):
    typ = arg.get("type", "nsobject")
    base_type = typ.rstrip("?")
    optional = typ.endswith("?")
    default = arg.get("default", "")
    if base_type in _OBJC_ENUM_TYPES:
        option_names = ", ".join(
            c_str(name) for name, _ in _OBJC_ENUM_TYPES[base_type])
        return (
            f"\tstatic const char *const {arg.get('name')}_options[] = "
            f"{{{option_names}, NULL}};\n"
            f"\t(void)luaL_checkoption(L, {idx}, NULL, "
            f"{arg.get('name')}_options);")
    if base_type == "string":
        fallback = c_str(default) if default else "NULL"
        return (f"\t(void)luaL_optstring(L, {idx}, {fallback});" if optional
                else f"\t(void)luaL_checkstring(L, {idx});")
    if base_type == "number":
        fallback = default or "0"
        return (f"\t(void)luaL_optnumber(L, {idx}, {fallback});" if optional
                else f"\t(void)luaL_checknumber(L, {idx});")
    if base_type == "integer":
        fallback = default or "0"
        return (f"\t(void)luaL_optinteger(L, {idx}, {fallback});" if optional
                else f"\t(void)luaL_checkinteger(L, {idx});")
    if base_type == "bool":
        return f"\t(void)lua_toboolean(L, {idx});"
    if base_type == "any":
        return f"\t(void)lua_type(L, {idx});"
    if base_type == "function":
        if optional:
            return (f"\tif (!lua_isnoneornil(L, {idx})) "
                    f"luaL_checktype(L, {idx}, LUA_TFUNCTION);")
        return f"\tluaL_checktype(L, {idx}, LUA_TFUNCTION);"
    if base_type == "table":
        return f"\tluaL_checktype(L, {idx}, LUA_TTABLE);"
    if base_type in ("nsobject", "nsview", "nswindow"):
        checker = {
            "nsobject": f"check_objc(L, {idx})",
            "nsview": f"check_view(L, {idx})",
            "nswindow": (f"lua_objc_check_object(L, {idx}, "
                         f"[NSWindow class], \"NSWindow\")"),
        }[base_type]
        if optional:
            return f"\tif (!lua_isnoneornil(L, {idx})) (void){checker};"
        return f"\t(void){checker};"
    raise ValueError(f"unknown argument type {typ!r}")


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
        lua_name   = cls.get("lua_name", cls_name)
        is_static  = cls.get("static", "false") == "true"
        detect_key = cls.get("detect")
        detect_cls = cls.get("detect_class")
        array_name = lua_name + "Methods"

        c_self_type = _OBJC_CLASS_TO_C_TYPE.get(cls_name, "id")
        self_class_expr = f"[{cls_name} class]"

        methods = cls.findall("method")

        # --- per-method generation ---
        for m in methods:
            mname = m.get("name")
            impl_mode = m.get("impl", "")
            has_impl = impl_mode == "true"
            stack_impl = impl_mode in ("stack", "class_stack")
            generated_body = impl_mode in ("constructor", "callback")
            wrapper_func = f"bridge_{cls_name}_{mname}"
            impl_func = f"bridge_{cls_name}_{mname}_impl"
            body_el = m.find("objc")
            args = m.findall("arg")

            # --- Forward declaration for _impl ---
            if generated_body:
                fwd_lines.append(f"static int {wrapper_func}(lua_State *L);")
            elif has_impl:
                arg_sig = ", ".join(
                    _LUA_TO_C_IMPL_TYPE.get(a.get("type"), "id") + " " + a.get("name")
                    for a in args
                )
                fwd_lines.append(f"static int {impl_func}(lua_State *L, {c_self_type}self{', ' + arg_sig if arg_sig else ''});")
            elif stack_impl:
                stack_func = (f"bridge_{mname}" if is_static
                              else f"{wrapper_func}_impl")
                fwd_lines.append(f"static int {stack_func}(lua_State *L);")

            # --- Wrapper function ---
            if generated_body:
                continue

            wrapper_lines.append(f"static int {wrapper_func}(lua_State *L) {{")
            if not is_static:
                if stack_impl:
                    wrapper_lines.append(
                        f"\t(void)lua_objc_check_object(L, 1, "
                        f"{self_class_expr}, {c_str(lua_name)});")
                else:
                    wrapper_lines.append(f"\tid _obj = lua_objc_check_object(L, 1, {self_class_expr}, {c_str(lua_name)});")
                    wrapper_lines.append(f"\t{c_self_type}self = ({c_self_type})_obj;")

            arg_names = []
            declared_arg_names = []
            for a in args:
                aname = a.get("name")
                atyp  = a.get("type", "nsobject")
                idx   = str(len(arg_names) + (1 if is_static else 2))
                if stack_impl:
                    wrapper_lines.append(stack_arg_check(a, idx))
                    arg_names.append(aname)
                    continue
                opt   = atyp.endswith("?")
                base_type = atyp[:-1] if opt else atyp
                dflt  = a.get("default", "")
                if base_type in _OBJC_ENUM_TYPES:
                    if opt:
                        raise ValueError(
                            f"{cls_name}.{mname}.{aname}: optional enums "
                            "are not supported")
                    enum_options = _OBJC_ENUM_TYPES[base_type]
                    option_names = ", ".join(
                        c_str(name) for name, _ in enum_options)
                    option_values = ", ".join(
                        value for _, value in enum_options)
                    wrapper_lines.append(
                        f"\tstatic const char *const {aname}_options[] = "
                        f"{{{option_names}, NULL}};")
                    wrapper_lines.append(
                        f"\tstatic const {base_type} {aname}_values[] = "
                        f"{{{option_values}}};")
                    wrapper_lines.append(
                        f"\t{base_type} {aname} = {aname}_values["
                        f"luaL_checkoption(L, {idx}, NULL, "
                        f"{aname}_options)];")
                    arg_names.append(aname)
                    declared_arg_names.append(aname)
                    continue
                check_fn = _LUA_TO_C_ARG_CHECK.get(atyp)
                if check_fn is None and opt:
                    check_fn = _LUA_TO_C_ARG_CHECK.get(base_type)
                if check_fn:
                    default_expr = c_str(dflt) if base_type == "string" else dflt
                    if opt and not dflt:
                        default_expr = "NULL" if base_type == "string" else "0"
                    wrapper_lines.append(
                        check_fn(idx, aname, opt, default_expr))
                    if base_type not in ("any", "table"):
                        declared_arg_names.append(aname)
                else:
                    raise ValueError(
                        f"{cls_name}.{mname}.{aname}: unknown argument type {atyp!r}")
                arg_names.append(aname)

            if body_el is not None:
                body_text = textwrap.dedent(body_el.text or "").strip()
                if not is_static and not re.search(r"\bself\b", body_text):
                    wrapper_lines.append("\t(void)self;")
                for declared_name in declared_arg_names:
                    if not re.search(
                            rf"\b{re.escape(declared_name)}\b", body_text):
                        wrapper_lines.append(f"\t(void){declared_name};")
                wrapper_lines.append(f"\t{{")
                for line in body_text.splitlines():
                    wrapper_lines.append(f"\t\t{line}")
                wrapper_lines.append(f"\t}}")
                wrapper_lines.append(f"\treturn 0;")
            elif has_impl:
                call_args = ", ".join(["L", "self"] + arg_names)
                wrapper_lines.append(f"\treturn {impl_func}({call_args});")
            elif stack_impl:
                stack_func = (f"bridge_{mname}" if is_static
                              else f"{wrapper_func}_impl")
                wrapper_lines.append(f"\treturn {stack_func}(L);")
            else:
                selector_parts = [mname] + [
                    a.get("label", a.get("name")) for a in args[1:]
                ]
                if args:
                    message = "[" + " ".join(
                        [f"self {selector_parts[0]}:{objc_arg_expr(args[0])}"] +
                        [f"{label}:{objc_arg_expr(arg)}"
                         for label, arg in zip(selector_parts[1:], args[1:])]
                    ) + "]"
                else:
                    message = f"[self {mname}]"
                objc_return(wrapper_lines, m.get("returns"), message)

            wrapper_lines.append("}")
            wrapper_lines.append("")

        if is_static:
            continue

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

    # Multiple classes may intentionally share one stack implementation
    # (for example NSWindow.layout and NSView.layout). Emit one declaration.
    fwd_lines = list(dict.fromkeys(fwd_lines))

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
# bridge_lib.inc
# ---------------------------------------------------------------------------

def gen_lib_entries(root, xml_path):
    entries = []
    for el in root:
        tag      = el.tag
        name     = el.get("name")
        lua_name = el.get("lua_name")
        if tag == "class" and el.get("static", "false") == "true":
            for method in el.findall("method"):
                method_lua_name = method.get("lua_name")
                if method_lua_name:
                    entries.append((
                        method_lua_name,
                        f"bridge_{el.get('name')}_{method.get('name')}"))
        elif tag == "struct":
            entries.append((name, f"bridge_{name}"))

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
    parser.add_argument("--xml", default="tools/AppKit.xml")
    parser.add_argument("--out", default="src/appkit/generated")
    args = parser.parse_args()

    tree = ET.parse(args.xml)
    root = tree.getroot()
    legacy_tags = {
        "method_group", "manual_entry", "constructor",
        "callback_setter", "prop",
    }
    for el in root.iter():
        if el.tag in legacy_tags:
            raise ValueError(
                f"<{el.tag}> is obsolete; use class methods and properties")
        for obsolete_attr in ("c_func", "src"):
            if obsolete_attr in el.attrib:
                raise ValueError(
                    f"{obsolete_attr}= is obsolete on <{el.tag}>")
    for el in root:
        if el.tag not in ("class", "struct"):
            raise ValueError(
                f"<{el.tag}> is not allowed at bridge scope; use <class> or <struct>")

    key_style = root.get("key_style", "enum")    # "enum" | "direct"
    cb_style  = root.get("callback_style", "property")  # "property" | "addTarget"

    os.makedirs(args.out, exist_ok=True)

    classes = root.findall("class")
    structs = {el.get("name"): el for el in root.findall("struct")}

    with open(os.path.join(args.out, "bridge_structs.m"), "w") as f:
        f.write(gen_structs(structs, args.xml))
    print(f"  wrote {args.out}/bridge_structs.m")

    # bridge_props.m
    if any(cls.find("properties") is not None for cls in classes):
        with open(os.path.join(args.out, "bridge_props.m"), "w") as f:
            f.write(gen_props(classes, structs, key_style, args.xml))
        print(f"  wrote {args.out}/bridge_props.m")

    # bridge_funcs.m
    hdr = make_header(args.xml)
    funcs = [hdr, "/* Generated bridge_xxx() functions */", ""]
    for cls in classes:
        for method in cls.findall("method"):
            function_name = (
                f"bridge_{cls.get('name')}_{method.get('name')}")
            if method.get("impl") == "constructor":
                funcs.append(gen_constructor(
                    method, key_style, cb_style, function_name))
            elif method.get("impl") == "callback":
                funcs.append(gen_callback_setter(
                    method, key_style, function_name))

    with open(os.path.join(args.out, "bridge_funcs.m"), "w") as f:
        f.write("\n".join(funcs))
    print(f"  wrote {args.out}/bridge_funcs.m")

    # bridge_lib.inc
    with open(os.path.join(args.out, "bridge_lib.inc"), "w") as f:
        f.write(gen_lib_entries(root, args.xml))
    print(f"  wrote {args.out}/bridge_lib.inc")

    # bridge_class_methods.m  (only if any <class> elements exist)
    if classes:
        with open(os.path.join(args.out, "bridge_class_methods.m"), "w") as f:
            f.write(gen_class_bindings(classes, key_style, args.xml))
        print(f"  wrote {args.out}/bridge_class_methods.m")

    print("Done.")


if __name__ == "__main__":
    main()
