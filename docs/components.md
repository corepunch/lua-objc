# Components

A component is a new XML tag written as an etlua template. It composes the
tags the vocabulary already has (stacks, `Arc`, `Label`, `SystemImage`), so
the same tag renders on AppKit and UIKit with no Objective-C and no view
code in Lua. The framework bundles a set of components, and any app can add
its own.

Run the gallery to see them all:

```sh
./lua-objc demo/component-gallery
```

## Bundled components

| Tag | Records | What it draws |
| --- | --- | --- |
| `<ActivityRings>` | `<ActivityRing value goal color label>` | Concentric progress rings like Activity. A second lap overlaps the first once the goal is passed. View children sit in the centre. |
| `<BarChart>` | `<BarMark value color label>` | Equal-width columns after Swift Charts' `BarMark`, scaled to the largest value or `maxValue`, tinted with `tint`. |
| `<CapacityBar>` | `<CapacitySegment value color label>` | A segmented capsule like the storage bar in System Settings. Segments take their share of `total`; the rest is a quaternary track. |
| `<HeatmapGrid>` | `<HeatmapCell value label>` | A contribution-style calendar: columns of `rows` cells whose opacity steps through `levels` bands of `tint`. |

The first four live in `lua/components/`: a template per tag, with a data
module beside it. Every component
accepts the usual frame attributes (`width`, `height`, `maxWidth`, `padding`,
`background`...) and an `accessibilityLabel` for VoiceOver.

```xml
<ActivityRings width="132" height="132" accessibilityLabel="Move 420 of 500 kcal">
  <ActivityRing value="420" goal="500" color="systemRed" />
  <ActivityRing value="24" goal="30" color="systemGreen" />
  <ActivityRing value="9" goal="12" color="systemCyan" />
</ActivityRings>

<CapacityBar total="994" accessibilityLabel="662 GB of 994 GB used">
  <CapacitySegment value="182" color="systemBlue" label="Applications" />
  <CapacitySegment value="480" color="systemPurple" label="Documents" />
</CapacityBar>
```

## Writing a component

A component is `<Tag>.etlua` in a `components/` folder. Put an app's own
components in `components/` beside `views/`. The renderer looks there first,
walking up from the folder of the template that uses the tag, and then in
`lua/components/`. The nearest one wins, so an app may have its own version
of a bundled component. Built-in tags are never components.

```
apps/<app>/
  views/Window.etlua          ← uses <SleepChart>
  components/SleepChart.etlua ← what the tag renders
  components/SleepChart.lua   ← optional: props, records, data
```

Before a template is compiled, each component tag is replaced by the
elements its template renders. A component is therefore ordinary template
content: the XML renderer remains the only caller of view constructors.

```xml
<!-- components/CapacityBar.etlua -->
<HStack spacing="<%= spacing %>" height="<%= height %>" maxWidth="infinity" cornerRadius="<%= radius %>" clipsToBounds="true">
  <% for index, segment in ipairs(segments) do -%>
  <VStack key="segment<%= index %>" background="<%= segment.color %>" flexGrow="<%= segment.weight %>" flexBasis="0" maxHeight="infinity" />
  <% end -%>
</HStack>
```

### The data module

An optional `<Tag>.lua` beside the template declares what the tag takes and
computes what the template draws. It never touches `ns` or a view
(`tests/app_architecture.test.lua` checks this).

```lua
local STYLE = { height = 12, spacing = 1 }

local CapacityBar = {
	-- Attributes handed to the template: "num", "bool", "str",
	-- or { type = "num", default = 4 }.
	props = { total = "num", spacing = "num" },
	-- Child tags read as data rather than views.
	records = { CapacitySegment = { value = "num", color = "str", label = "str" } },
}

-- Geometry is a plain function, so tests check it without views.
function CapacityBar.segments(records, total) ... end

-- Further template variables. `attrs` holds every attribute as written,
-- for geometry that depends on the frame.
function CapacityBar.data(props, records, attrs)
	local height = tonumber(attrs.height) or STYLE.height
	return { segments = CapacityBar.segments(records, props.total), height = height,
		radius = height / 2, spacing = props.spacing or STYLE.spacing }
end

return CapacityBar
```

The template sees each declared prop by name, `records` (the record
children in document order, each with its `tag`), and whatever `data`
returns. Without a module the tag takes no props and no records.

### Attributes and content

- Every attribute that is not a declared prop goes to the template's root
  element, over the root's own: `id`, `width`, `maxWidth`, `padding`,
  `background`, `transition`, `accessibilityLabel`. A template renders
  exactly one root element.
- View children replace the template's `<ContentPresenter />`, as in WPF. A
  component without one takes no content.
- An action is an attribute like any other: declare `onSelect = "str"` and
  pass it on, `<Button action="<%= onSelect %>" />`.
- Do not give elements inside a component an `id`: refs are per template,
  and two uses of the component would claim the same one. The `id` on the
  tag names the component's root.

Prefer flex weights (`flexGrow` with `flexBasis="0"`) over computed pixel
widths. The native layout engine then splits whatever space the component is
offered, and it resizes with the window.

### Retained updates

A component's elements are reconciled like the rest of the template
(see [retained-templates.md](retained-templates.md)): changed attributes are
applied to the existing views. Give repeated
elements a `key` so added or removed records insert and remove their own
views:

```xml
<Arc key="ring<%= index %>.lap" startAngle="<%= arc.startAngle %>" endAngle="<%= arc.endAngle %>" ... />
```

## Rules

- A component composes native views; it never imitates a system control. Use
  `Gauge`, `ProgressView`, `Toggle` and the rest where one exists.
- A component is a template. If a tag cannot be drawn with the vocabulary,
  extend the vocabulary in the framework; do not build views in Lua.
- Keep geometry in plain functions on the module and test them headlessly,
  as `tests/components.test.lua` does for the bundled set.
- Reusable structure with no attributes of its own can stay a `partial()`.

## Resources in components

A component's template may use the app's resources (`width="@symbolColumn"`);
they resolve after the component expands. A `<Resources>` element inside a
component scopes to its parent element, as in any template. See
[data-driven.md](data-driven.md#resources).
