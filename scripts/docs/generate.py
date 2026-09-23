#!/usr/bin/env python3
"""Generate Markdown API reference from structured Lua docblocks.

Docblock format (in .lua sources, directly above the documented function):

    --- One-line summary.
    ---
    --- Overview prose (why, behavior, layout contract, edge cases).
    --- @tag Button
    --- @prop title string required. Button label. Use a precise verb.
    --- @prop action function optional. Called with sender.
    --- @platform AppKit NSButton. UIKit UIButton.
    --- @example ns.Button { title = "Save" }
    --- @see Link, Toggle

Only triple-dash (`---`) comment lines form a docblock. The block attaches
to the next `function <Module>.<Name>(` line (blank lines allowed).

Output mirrors the SwiftUI page shape: title + summary, declaration,
overview, properties, examples, platform notes, see also. Files carry a
"generated — do not edit" header pointing back to the Lua source.

Stdlib only so docs build on Linux CI where ./lua-objc (macOS-only)
cannot run.
"""

import argparse
import os
import re
import sys

FUNC_RE = re.compile(r"^function\s+([\w\.]+)\s*[\(:]")
PROP_RE = re.compile(r"^(\S+)\s+(\S+)\s+(required\.|optional\.)\s*(.*)$")
UI_CONSTRUCTORS = {
    "Window", "Panel", "Sheet", "MenuItem", "Preview", "TabView", "VStack",
    "HStack", "FlowStack", "Section", "GroupBox", "Form", "LabeledContent",
    "ControlGroup", "DisclosureGroup", "OutlineGroup", "ScrollView", "HSplit",
    "VSplit", "Separator", "Divider", "Grid", "Text", "ZStack", "TextField",
    "SearchField", "TextEditor", "Title", "Image", "SystemImage", "Spacer",
    "List", "OutlineView", "Button", "Link", "ContentUnavailable", "Toggle",
    "Slider", "Stepper", "Picker", "DatePicker", "ColorPicker", "ProgressView",
    "PathView", "Curve", "NavigationStack", "NavigationLink", "Alert", "Label",
    "PageControl", "LinearGradient", "Menu", "MaterialView", "ToolbarItem",
}


def parse_file(path):
    """Return (blocks, public_funcs). blocks: list of dicts."""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    blocks = []
    public_funcs = []  # (name, lineno)
    pending = []  # docblock lines
    pending_start = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("---"):
            if not pending:
                pending_start = i + 1
            text = stripped[3:]
            if text.startswith(" "):
                text = text[1:]
            pending.append(text)
        elif stripped == "" and pending:
            # Blank line inside/after a docblock: keep only if more
            # docblock lines follow (lookahead), else flush as dangling.
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            if j < len(lines) and lines[j].strip().startswith("---"):
                pending.append("")
            else:
                # Dangling comment block; drop it.
                pending = []
            # Fall through to func check on blank line (no match).
        elif pending and stripped.startswith("--") and not stripped.startswith("---"):
            # Ordinary comment breaks the docblock attachment.
            pending = []
        else:
            m = FUNC_RE.match(stripped)
            if m:
                public_funcs.append((m.group(1), i + 1))
                if pending:
                    blocks.append(build_block(pending, path, pending_start, m.group(1)))
                    pending = []
            elif pending and stripped != "":
                # Non-comment, non-function line: docblock was dangling.
                pending = []
        i += 1
    documented = {block["func"] for block in blocks}
    # Every exported, capitalized Lua entry point gets a page. Docblocks add
    # authored API detail; the function declaration still provides a useful
    # index entry when detail has not been written yet.
    for name, lineno in public_funcs:
        leaf = name.split(".")[-1]
        if leaf[:1].isupper() and name not in documented:
            blocks.append({
                "tag": leaf,
                "summary": "%s API entry point." % leaf,
                "overview": "This public entry point is indexed automatically from its Lua declaration. Add a docblock above the implementation to describe its behavior, properties, and examples.",
                "props": [], "methods": [], "examples": [], "platforms": [], "see": [],
                "func": name, "source": "%s:%d" % (path, lineno),
            })
    return blocks, public_funcs


def build_block(doclines, path, start_lineno, func_name):
    summary_lines = []
    overview_lines = []
    tags = {"prop": [], "example": [], "platform": [], "see": [], "method": []}
    tag = None
    seen_overview = False
    for dl in doclines:
        if dl.startswith("@"):
            seen_overview = True
            parts = dl.split(None, 1)
            key = parts[0][1:]
            rest = parts[1] if len(parts) > 1 else ""
            if key == "tag":
                tag = rest.strip()
            elif key in tags:
                tags[key].append(rest.strip())
            # Unknown @keys are ignored so prose can evolve freely.
        elif not seen_overview:
            summary_lines.append(dl)
        else:
            overview_lines.append(dl)
    # First non-empty line is the summary; the rest is overview lead-in.
    full = [l for l in summary_lines]
    summary = next((l for l in full if l.strip()), "")
    overview_rest = [l for l in full if l is not summary]
    overview = "\n".join(overview_rest + overview_lines).strip()
    if tag is None:
        # Default tag: trailing component of function name.
        tag = func_name.split(".")[-1]
    return {
        "tag": tag,
        "summary": summary.strip(),
        "overview": overview,
        "props": tags["prop"],
        "methods": tags["method"],
        "examples": tags["example"],
        "platforms": tags["platform"],
        "see": tags["see"],
        "func": func_name,
        "source": "%s:%d" % (path, start_lineno),
    }


def parse_prop(line):
    m = PROP_RE.match(line)
    if not m:
        return None
    name, ptype, req, desc = m.groups()
    return (name, ptype, req[:-1], desc)


def render_markdown(block, known_tags=None):
    tag = block["tag"]
    known = known_tags or set()
    out = []
    out.append("<!-- GENERATED from %s — do not edit by hand. -->" % block["source"])
    out.append("")
    out.append("# %s" % tag)
    out.append("")
    if block["summary"]:
        out.append(block["summary"])
        out.append("")
    out.append("```xml")
    out.append("<%s ... />" % tag)
    out.append("```")
    out.append("")
    if block["overview"]:
        out.append("## Overview")
        out.append("")
        out.append(block["overview"])
        out.append("")
    if block["props"]:
        out.append("## Topics")
        out.append("")
        out.append("### Properties")
        out.append("")
        out.append("| Name | Type | Required | Description |")
        out.append("|---|---|---|---|")
        for p in block["props"]:
            parsed = parse_prop(p)
            if parsed:
                name, ptype, req, desc = parsed
                out.append("| `%s` | %s | %s | %s |" % (name, ptype, req, desc))
            else:
                out.append("| | | | %s |" % p)
        out.append("")
    if block["methods"]:
        out.append("### Methods")
        out.append("")
        for m in block["methods"]:
            out.append("- `%s`" % m)
        out.append("")
    if block["examples"]:
        out.append("## Example")
        out.append("")
        for ex in block["examples"]:
            out.append("```etlua")
            out.append(ex)
            out.append("```")
            out.append("")
    if block["platforms"]:
        out.append("## Platform notes")
        out.append("")
        for p in block["platforms"]:
            out.append("- %s" % p)
        out.append("")
    if block["see"]:
        refs = []
        for s in block["see"]:
            refs.extend([r.strip() for r in s.split(",") if r.strip()])
        if refs:
            out.append("## See Also")
            out.append("")
            for r in refs:
                if r in known:
                    out.append("- [%s](%s.md)" % (r, r))
                else:
                    # No page generated yet: plain reference, no dead link.
                    out.append("- `%s`" % r)
            out.append("")
    out.append("---")
    out.append("")
    out.append("_Source: `%s` (`%s`)_" % (block["source"], block["func"]))
    out.append("")
    return "\n".join(out)


def render_index(blocks):
    out = []
    out.append("<!-- GENERATED — do not edit by hand. -->")
    out.append("")
    out.append("# Reference")
    out.append("")
    out.append("Every exported component and public API entry point is indexed here.")
    out.append("Pages include authored details when available and are discovered from")
    out.append("the AppKit and UIKit Lua modules.")
    out.append("")
    out.append("| Component | Summary |")
    out.append("|---|---|")
    for b in sorted(blocks, key=lambda b: b["tag"].lower()):
        out.append("| [%s](%s.md) | %s |" % (b["tag"], b["tag"], b["summary"]))
    out.append("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", nargs="+", required=True,
                    help="Lua source files to scan for --- docblocks")
    ap.add_argument("--out", required=False, default=None,
                    help="Output directory for .md files")
    ap.add_argument("--check", action="store_true",
                    help="Validate only; do not write output")
    ap.add_argument("--strict", action="store_true",
                    help="With --check, fail on public functions missing authored docblocks")
    args = ap.parse_args(argv)

    if not args.check and not args.out:
        ap.error("--out is required unless --check is given")

    all_blocks = []
    all_funcs = []
    errors = []
    for src in args.src:
        if not os.path.isfile(src):
            errors.append("source not found: %s" % src)
            continue
        blocks, funcs = parse_file(src)
        for b in blocks:
            if not b["summary"]:
                errors.append("%s: @tag %s has no summary line" % (b["source"], b["tag"]))
        all_blocks.extend(blocks)
        all_funcs.extend([(src, n, ln) for (n, ln) in funcs])

    documented_funcs = set(b["func"] for b in all_blocks
                           if not b["overview"].startswith("This public entry point is indexed automatically"))

    # Collapse platform duplicates and aliases onto one reference page. Prefer
    # an authored docblock over an automatically indexed declaration.
    unique_blocks = {}
    for block in all_blocks:
        previous = unique_blocks.get(block["tag"])
        if previous is None or (previous["overview"].startswith("This public entry point is indexed automatically")
                                and not block["overview"].startswith("This public entry point is indexed automatically")):
            unique_blocks[block["tag"]] = block
    all_blocks = list(unique_blocks.values())

    # Undocumented public functions (heuristic: Module.Name assignments).
    if args.strict:
        for (src, name, ln) in all_funcs:
            if name not in documented_funcs and not name.startswith("_"):
                leaf = name.split(".")[-1]
                if leaf in UI_CONSTRUCTORS:
                    errors.append("%s:%d: %s has no --- docblock" % (src, ln, name))

    if args.check:
        for e in errors:
            print("docs: error: %s" % e, file=sys.stderr)
        if args.strict:
            total = sum(1 for (_, n, _) in all_funcs
                        if n.split(".")[-1][:1].isupper())
            print("docs: %d pages, %d public constructors, %d error(s)"
                  % (len(all_blocks), total, len(errors)))
        return 1 if errors else 0

    os.makedirs(args.out, exist_ok=True)
    known = set(b["tag"] for b in all_blocks)
    for b in all_blocks:
        dest = os.path.join(args.out, b["tag"] + ".md")
        with open(dest, "w", encoding="utf-8") as f:
            f.write(render_markdown(b, known))
    with open(os.path.join(args.out, "index.md"), "w", encoding="utf-8") as f:
        f.write(render_index(all_blocks))
    print("docs: wrote %d pages to %s/" % (len(all_blocks), args.out))
    for e in errors:
        print("docs: warning: %s" % e, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
