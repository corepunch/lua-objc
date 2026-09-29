# Lua components

A component is a new XML tag written in Lua. It composes the native views
every platform already has (stacks, `Arc`, `Label`, `SystemImage`), so the same
tag renders on AppKit and UIKit with no Objective-C. `SectorChart` (the 3D pie
in Disk Map) was the first of these. `ui/component.lua` turns that pattern
into a public API. The framework bundles a set of components, and any app
can add its own.

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
| `<SectorChart>` | `<SectorMark>` | Pie, donut, sunburst and raised 3D sectors (see the project reference). |

The first four live in `lua/components/`, one file per tag. Every component
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

A component is a module that returns a definition table. Put an app's own
components in `components/` beside `views/`. The renderer looks there first,
walking up from the template's folder, and then in `lua/components/`. Tags
are global, so a module found for a tag that another module already defined
is an error rather than a substitute. The file name is the tag name:

```
apps/<app>/
  views/Window.etlua        ← uses <SleepChart>
  components/SleepChart.lua ← defines it
```

```lua
local Component = require("ui.component")

-- Named constants, not literals in the view code.
local STYLE = { height = 12, spacing = 1 }

local CapacityBar = {
	-- XML attributes, typed like the built-in schema ("num", "bool", "str",
	-- or { type = "num", default = 4 }).
	props = { total = "num", spacing = "num" },
	-- Record child tags and their attributes.
	records = { CapacitySegment = { value = "num", color = "str", label = "str" } },
	-- Attributes bound to controller actions: onSelect="select".
	actions = {},
}

-- Geometry is a plain function, so tests check it without views.
function CapacityBar.segments(records, total) ... end

function CapacityBar.build(self, ns)
	local bar = Component.frame(self, { spacing = STYLE.spacing, fixedHeight = STYLE.height })
	for _, segment in ipairs(CapacityBar.segments(self.records, self.props.total)) do
		table.insert(bar, ns.VStack { background = segment.color, flexGrow = segment.weight, flexBasis = 0 })
	end
	return ns.HStack(bar)
end

return CapacityBar
```

`build(self, ns)` returns one native view. `self` carries:

- `props`: the declared attributes, coerced and with defaults applied;
- `records`: the record children, in document order;
- `content`: view children, such as a label layered over a chart;
- `actions`: the bound callbacks;
- `layout`: the frame attributes the template gave the tag.
  `Component.frame(self, defaults)` merges them over the component's own
  defaults for the root view.

Prefer flex weights (`flexGrow` with `flexBasis = 0`) over computed pixel
widths. The native layout engine then splits whatever space the component is
offered, and it resizes with the window.

### Retained updates

Without `update`, a template reconcile rebuilds the component whenever its
attributes or records change. With `update`, the component moves its existing
views. Inside `ns.withAnimation` those changes animate, like SwiftUI
interpolating a trimmed shape:

```lua
-- Optional: decline a change that cannot be applied in place; the node is
-- then rebuilt instead.
function CapacityBar.accepts(self, props, records)
	return #CapacityBar.segments(records, props.total) == #self.segments
end

function CapacityBar.update(self, ns)
	-- self.props and self.records now hold the new values.
	for index, segment in ipairs(CapacityBar.segments(self.records, self.props.total)) do
		self.segments[index].flexGrow = segment.weight
	end
end
```

`accepts` runs while the reconciler plans, before anything on screen changes.
`update` runs when the plan applies. Use `ns._motionInsert(self.view, view,
index)` and `ns._motionRemove(view)` to add or remove children so they play
their transitions. A change to `width` or `height` always rebuilds, because
component geometry is derived from the frame.

## Rules

- A component composes native views; it never imitates a system control. Use
  `Gauge`, `ProgressView`, `Toggle` and the rest where one exists.
- Components are the one app-layer place that calls `ns` view constructors.
  Controllers still render templates only. A component never creates a
  window (`tests/app_architecture.test.lua` checks this).
- Keep geometry in plain functions on the module and test them headlessly,
  as `tests/components.test.lua` does for the bundled set.
- Tags are global. An app component may not reuse a built-in tag, and two
  modules may not define the same tag.
