---
layout: default
title: XML syntax
---

# XML syntax

`lua/ui/xml.lua` is the source of truth for the cross-platform XML registry.
Templates are processed by etlua first and then compiled into native AppKit or
UIKit views. The same template can therefore be rendered with `ns = require("AppKit")`
or `ns = require("UIKit")`.

Templates are the only place application view structure is defined. Controllers
provide data, render a template, retain its `refs`, and bind behavior to those
refs. See [application architecture](application-architecture.md) for the
model/controller/view boundary.

Render a file with:

```lua
local xml = require("ui.xml")
local view, refs = xml.renderFile("apps/mail/views/Window.etlua", data, ns)
```

XML attributes are strings when parsed. The registry coerces layout numbers and
boolean values for supported attributes. Unknown tags are errors; unsupported
attributes are ignored unless the tag documents them below.

## Sizing

Use [WPF layout conventions](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/alignment-margins-and-padding-overview)
as the reference when an XML API design is ambiguous. Keep camelCase names and
the SwiftUI-style native behavior documented here.

Use `width` and `height` for fixed dimensions, `minWidth`/`minHeight` for
minimums, and `maxWidth`/`maxHeight` for maximums. Set a maximum to `infinity`
to expand along that axis, corresponding to SwiftUI's `.frame(maxWidth:
.infinity)` or `.frame(maxHeight: .infinity)`. Omitting a dimension keeps the
control's natural sizing behavior. Fixed dimensions must be finite,
nonnegative numbers; zero is supported.

```etlua
<VStack padding="20" spacing="14" alignment="leading">
  <Image path="<%= game.cover %>" maxWidth="infinity" height="280"
         contentMode="fill" cornerRadius="16" />
</VStack>
```

Omit sizing wherever the SwiftUI reference omits it. A stack derives its size
from its children; labels keep their intrinsic width and wrap against the
parent proposal. Use stack `alignment="leading"` for leading text, not an
infinite width on each label. Text fields accept available width by default.
Gradients fill both proposed dimensions. `Image resizable="true"` accepts its
parent's proposal; `contentMode` chooses how the image draws in that rectangle.
A horizontal-only `ScrollView` derives its height from its content, so do not
calculate content width from item counts or hard-code the strip height.

A plain native button can contain one label view (including a stack). Its size
and flexibility come from that content. This is the XML equivalent of a SwiftUI
button label closure and follows WPF's content-control convention:

```etlua
<Button style="plain" action="open" accessibilityLabel="Open adventure">
  <VStack width="142" spacing="8" alignment="leading">
    <Image path="<%= game.cover %>" resizable="true" contentMode="fill"
           width="130" height="176" />
    <Label text="<%= game.title %>" lines="1" />
  </VStack>
</Button>
```

Use `ZStack alignment="bottomLeading"` to position naturally sized overlay
content; do not stretch it and add a spacer just to position it at the bottom.

The removed `fillWidth`, `fillHeight`, `fixedWidth`, and `fixedHeight`
attributes are errors. These names belong to native layout storage, not the
XML vocabulary. `Window` and `Column` retain their own dimension properties.

## Containers

| Tag | Purpose | Important attributes |
|---|---|---|
| `Window` | Window configuration and root content | `title`, `width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`, `appearance`, `tabbingMode`, `tabbingIdentifier`, `toolbarLabels`, `visible`, `sidebarWidth` |
| `VStack` | Vertical native stack | `padding`, `paddingHorizontal`, `paddingVertical`, `spacing`, `alignment`, `flexGrow`, `flexShrink`, `width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`, `hidden` |
| `HStack` | Horizontal native stack | Same layout attributes as `VStack` |
| `LazyVStack` | Virtualized native vertical collection | `rowHeight`, `spacing`, `reorderable`, `reorderContainer`, plus layout attributes |
| `LazyVGrid` | Virtualized native grid collection | `columns`, `rowHeight`, `spacing`, `reorderable`, `reorderContainer`, plus layout attributes |
| `Grid` / `FlowStack` | Eager grid / wrapping layout | `spacing`, `reorderable`, `reorderContainer`, plus layout attributes |
| `HSplit` | Horizontal split container | Same layout attributes as `VStack`; use `Window sidebar/content` for a window-level sidebar |
| `ScrollView` | Native scroll container for one content child | `contentWidth`, `contentHeight`, `horizontal`, `vertical`, plus layout attributes |
| `Spacer` | Flexible spacing view | Layout attributes |
| `Divider` | Native separator | `orientation`, plus layout attributes |

Stacks contain child tags. `Window` may contain one content view, multiple
content views, and a `Toolbar` block. It returns window configuration to the
caller rather than creating a window directly in the XML compiler.

Use `reorderable="true"` with `reorderContainer="actionName"` on a stack,
grid, flow layout, or `List`. The controller action receives a one-based
`ui.reorder.Difference`; apply it in the model and refresh a retained template.
Lazy collection children must each render one view. Their item descriptions
are parsed up front, but native views are created only for visible cells.
`rowHeight` is fixed, so provide enough room for the supported text sizes.

## Content and input

| Tag | Purpose | Important attributes |
|---|---|---|
| `Label` / `Text` | Native non-editable label | `text` or `value`, `size`, `weight`, `color`, `lines`, `truncation`, plus layout attributes |
| `Title` | Bold window/header text | `text` or `value` |
| `TextEditor` | Native editable text view | `text` or `value`, `size`, `weight`, `editable`, `selectable`, `wrapMode`, `drawsBackground`, plus layout attributes |
| `TextField` | Native single-line field | `value` or `text`, `placeholder`, `editable`, `bezeled`, `bordered`, `size`, plus layout attributes |
| `Button` | Native push button | `title` or `label`, `subtitle`, `systemImage`, `style`, `detail`, plus layout attributes |
| `Toggle` / `Switch` | Native checkbox/toggle | `label`, `value` or `checked`, plus layout attributes |
| `Slider` | AppKit `NSSlider` | `min`, `max`, `value`, `tickMarks`, `allowsTickMarkValuesOnly`, plus layout attributes |
| `Stepper` | AppKit `NSStepper` | `min`, `max`, `value`, `increment`, `wraps`, `autorepeat`, plus layout attributes |
| `Picker` | AppKit `NSPopUpButton` | zero-based `value`, plus one or more `Option` children |
| `Option` | Child descriptor consumed by `Picker` | `title`, `label`, or `value` |
| `Image` | Native image view or SF Symbol | `src`/`path`, or `system`/`symbol`; `label`, `size`, `weight`, `color`, `resizable`, `contentMode` |
| `SystemImage` | Native SF Symbol image | `name` or `symbol`, `label`, `size`, `weight`, `color` |
| `Chart` | Pre-built chart supplied in render data | `data` key, default `chart` |

XML callbacks are normally attached in the controller after rendering. Keep
business logic out of templates. For a button or toggle whose callback must be
attached after rendering, use `ref` and the returned `refs` table; do not
rebuild the surrounding view tree in the controller.

`Slider`, `Stepper`, and `Picker` are currently AppKit-only. Do not place them
in a template that must render on UIKit until matching UIKit controls exist.

```xml
<Slider min="0" max="100" value="60" tickMarks="6" />
<Stepper min="0" max="20" value="4" increment="1" />
<Picker value="1">
  <Option title="Low" />
  <Option title="Medium" />
  <Option title="High" />
</Picker>
```

## Lists and toolbars

| Tag | Purpose | Important attributes |
|---|---|---|
| `List` | Native table/list | `style`, `header`, `alternatingRows`, `bordered`, `gridLines`, plus layout attributes |
| `Column` | Child column descriptor consumed by `List` | `id`, `title`, `width`, `minWidth`, `alignment` |
| `Toolbar` | Toolbar item collection consumed by `Window` | No attributes |
| `ToolbarItem` | Native toolbar descriptor; accepts at most one view child as its custom control | `id`, `label`, `icon`, `tooltip`, `action`, `bordered` |

A `List` requires at least one `Column`. Rows are supplied by the controller at
runtime with `list:replaceRows(rows)`. Use `style="sourceList"` for sidebar
navigation, `style="plain"` or `style="fullWidth"` for primary data, and
`style="inset"` for grouped settings.

## etlua helpers

The XML renderer supports normal etlua expressions and these helpers:

```etlua
<% for _, article in ipairs(articles) do %>
  <Label text="<%= article.title %>" />
<% end %>
```

- `partial(path, data)` includes another template.
- `extends(path, data)` selects a parent template.
- `block(name, content)` defines content for a parent.
- `yield(name)` emits a child block.

Use XML entities in attributes and text: `&amp;`, `&lt;`, `&gt;`, `&quot;`, and
`&apos;`. The parser also decodes decimal and hexadecimal numeric entities.

## Source and drift control

When adding a cross-platform tag, update the registry in `lua/ui/xml.lua`, add
a focused XML test in `tests/`, and update this page. Keep this page aligned
with the registry so agents can treat it as a checked-in syntax contract.
