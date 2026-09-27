# Animation, motion and retained updates

lua-objc animates the way SwiftUI does: a state change made inside a
transaction animates every view it affects, and views that appear or leave
play their transitions. The same engine drives AppKit and UIKit.

| Piece | Where |
|---|---|
| Animation values, transitions, keyframes, `withAnimation` | `lua/ui/animation.lua` |
| Core Animation engine (transactions, transitions, matched geometry) | `src/shared/motion.m`, glue in `src/appkit/motion.m` and `src/uikit/bridge.m` |
| Retained templates and reconciliation | `lua/ui/template.lua`, `xml.mount` / `xml.reconcile` in `lua/ui/xml.lua` |
| Automatic layout after writes | `src/appkit/layout.m` (“Automatic invalidation”), `src/uikit/layout.m` |
| Charts that update in place | `lua/ui/sectors.lua` |
| Tests | `tests/animation.test.lua`, `tests/template_mount.test.lua`, `tests/auto_layout.test.lua`, `tests/sector_chart.test.lua`, `tests/motion_feedback.test.lua` |

## Transactions

```lua
ns.withAnimation(ns.Animation.snappy(), function()
	template:update(data)          -- or any view property writes
end, function()
	-- runs once every animation started here has finished
end)
```

`ns.withAnimation(animation, body, completion)` is SwiftUI's
`withAnimation { state = … }`. While `body` runs, the engine snapshots what
the body touches: a Lua property write records the view's paint state
(opacity, transform, colour, corner radius, content) and, for writes that
affect layout, the geometry of its layout owner's subtree. Structural edits
record their container the same way. At the end it lays out, compares, and
animates each changed layer from its old value (or the on-screen value, when
an earlier animation is still running) to the new model value.

Model values are never changed by animation. An interrupted, skipped or
reduced animation always ends exactly where layout put the view, so code can
read frames immediately after the body without waiting for the animation.

- `ns.withAnimation(body)` uses the default animation (a spring without
  bounce).
- `ns.withAnimation(nil, body)` applies the changes without animating, even
  inside an outer transaction.
- `ns.withTransaction(ns.Transaction { animation = …, disablesAnimations =
  true }, body)` is the explicit form.
- Outside any transaction, writes apply immediately and inserted views appear
  without a transition.

### Animation values

`ns.Animation` mirrors SwiftUI's `Animation`:

| Value | Notes |
|---|---|
| `linear(d)`, `easeIn(d)`, `easeOut(d)`, `easeInOut(d)` | Default duration 0.35 s. |
| `timingCurve(x1, y1, x2, y2, d)` | Cubic Bézier. |
| `spring{duration, bounce}` or `spring{response, dampingFraction}` | Also `spring(duration, bounce)`. A negative bounce overdamps. |
| `smooth()`, `snappy()`, `bouncy()` | Presets with bounce 0, 0.15 and 0.3; accept `{duration, extraBounce}`. |
| `interactiveSpring()` | Short, stiff; for tracking direct manipulation. |
| `interpolatingSpring(stiffness, damping)` | Physical parameters. |
| `default` | `spring()`. |

Modifiers return new values: `:delay(s)`, `:speed(x)`,
`:repeatCount(n, autoreverses)`, `:repeatForever(autoreverses)`. XML
attributes accept the same names as strings, for example
`animation="snappy"` or `animation="easeOut(0.2)"`.

## Transitions

A transition plays when a view is inserted or removed **inside an animated
transaction**; removed views stay on screen until their removal finishes.
Changing `hidden` inside a transaction plays the same transitions.

```xml
<VStack id="pageContent" transition="opacity">…</VStack>
<SectorChart transition="drawOn" …>…</SectorChart>
<Label transition="asymmetric(move(top), opacity)" … />
```

| Transition | Effect |
|---|---|
| `opacity` | Fade. |
| `scale(0.8)` | Scale from/to the factor. |
| `slide` | In from the leading edge, out to the trailing edge. |
| `move(top)` | In from and out to an edge (`top`, `bottom`, `leading`, `trailing`). |
| `offset(x, y)` | From/to an offset. |
| `push(trailing)` | In from the edge and out toward the opposite one, fading. |
| `drawOn` | Arcs inside the view stroke themselves in, staggered (charts). |
| `identity` | No transition. |
| `a+b` | Combined, for example `opacity+scale(0.9)`. |
| `asymmetric(a, b)` | Separate insertion and removal. |

`ns.transition(view, t)` is the imperative form; `nil` removes it. Under
Reduce Motion, moving transitions become fades.

## Other motion attributes

These XML attributes apply to any view and patch in place on reconcile:

| Attribute | SwiftUI |
|---|---|
| `opacity`, `scaleEffect`, `rotationEffect`, `offsetX`, `offsetY` | `.opacity`, `.scaleEffect`, `.rotationEffect`, `.offset` |
| `animation` + `animationValue` | `.animation(_:value:)`: when `animationValue` changes and no transaction is open, that template update animates with `animation`. |
| `matchedGeometry` + `matchedGeometryNamespace` | `.matchedGeometryEffect`: a view that appears as its match leaves grows from where the other was. |
| `contentTransition` | `opacity`, `numericText`, `interpolate` or `identity` for text, title and image changes. |
| `symbolEffect`, `symbolEffectActive`, `symbolEffectValue` | `.symbolEffect`: `bounce`, `pulse`, `variableColor`, `scale`, `wiggle`, `rotate`, `breathe`, … Repeating while active, or once each time `symbolEffectValue` changes. |

Lua-only animators:

- `ns.keyframeAnimation(view, {tracks = {scaleEffect = {{type = "spring",
  value = 1.2, duration = 0.2}}}}, completion)` is `KeyframeAnimator`.
  Tracks: `opacity`, `scaleEffect`, `rotationEffect`, `offsetX`, `offsetY`.
- `ns.phaseAnimation(view, {phases = {…}, animation = …, repeating = false})`
  is `PhaseAnimator`; it returns a handle with `cancel()`, which the current
  `Scope` also calls when disposed.
- `ns.symbolEffect(view, effect, options)` plays an SF Symbol effect.
- `ns.reduceMotion()` reports the accessibility setting.

## Retained templates and reconciliation

Screens are etlua templates mounted once through `ui.template`; later
`template:update(data)` calls reconcile the new description against the
mounted views instead of rebuilding them. An update whose data is unchanged
does nothing.

How nodes match and what happens to them:

1. **Matching.** Nodes match by tag and `id` (or `key`), otherwise by tag
   and order among their siblings.
2. **Patch in place.** A matched node keeps its native view, state and focus
   when every changed attribute can be applied to it:
   - any view: `hidden`, `opacity`, `scaleEffect`, `rotationEffect`,
     `offsetX`, `offsetY`, `cornerRadius`, `background`, `transition`,
     `matchedGeometry`, `contentTransition`, `disabled`,
     `accessibilityLabel`, the `symbolEffect` attributes, and motion
     metadata (`animation`, `animationValue`, `key`);
   - layout: `width`, `height`, `min…`/`max…`, `flexGrow`, `flexShrink`,
     `flexBasis`, and on stacks `padding…`, `spacing`, `alignment`;
   - per tag: `Label`/`Paragraph`/`TextField` `text`, `Paragraph`
     `revealedCharacters` (typewriter reveal), `Button` `title`,
     `ProgressView`/`Gauge`/`Slider`/`Picker` `value`.
3. **Stacks** (`VStack`, `HStack`, `ZStack`, `FlowStack`) insert, move and
   remove children individually; keyed children move rather than being
   rewritten.
4. **Records** (`SectorMark`, `TreemapNode`, `Column`, …) configure their
   parent. A tag whose schema entry has `updateRecords(view, records)` takes
   changed records in place: `SectorChart` moves its existing arcs to the new
   angles, adds or removes arcs below its overlay, and keeps its hover and
   keyboard handling (`Sectors.update` in `lua/ui/sectors.lua`). Its other
   children reconcile normally. Any other record change rebuilds the parent.
5. **Rebuild.** Any other change rebuilds that one node: a new native view
   replaces the old one, inside the current transaction.

Planning builds new subtrees and validates every change before touching the
screen, so a render error keeps the old view.

### Layout after structural changes

Inserting, moving or removing a view (`_motionInsert`, `_motionRemove`)
schedules layout exactly like a layout-affecting property write. AppKit lays
out dirty owners once per run-loop turn, before the loop sleeps and Core
Animation commits; UIKit marks the owner `setNeedsLayout`. A view added by an
update is therefore placed before it is first drawn, and never appears at its
container's origin. A Lua geometry read (`frame`, `size`, `fittingSize`, …)
flushes pending layout first. Apps never call `layout()`.

### Keeping live updates steady

Progress updates (a scan, a download) usually arrive outside any transaction,
many times a second. They should change values, not structure:

- Give rows that can re-rank a `key` so they move instead of rewriting each
  other's text.
- Give changing values a fixed width (`width` with `alignment="trailing"`)
  so “Calculating…” and “≥ 998.9 MB” occupy the same space.
- Prefer one view with changing attributes over an `if` that swaps between
  different tags; every swap rebuilds that node.
- Put charts' changing data in their records (`SectorMark` values) and let
  `updateRecords` apply it; entrance transitions such as `drawOn` then play
  once, not on every update.
- Keep `withAnimation` for user-driven changes (navigation, selection,
  disclosure). Diskmap animates page changes (`Controller:show`) but applies
  scan progress immediately.

Diskmap's overview is the reference case: during a 30-second scan the donut
is never rebuilt and legend rows never overlap
(`apps/diskmap/views/Hero.etlua`, `LegendRow.etlua`).

## Testing

Headless tests run the same engine without a window server:

| Hook | Use |
|---|---|
| `ns._motionOverrideReduceMotion(true/false/nil)` | Pin Reduce Motion; `nil` follows the system. |
| `ns._motionAnimations(view)` | Animations the engine added to a view's layer. |
| `ns._motionSettle()` | Finish every running animation now, running completions and removals. |
| `ns._motionIsLeaving(view)` | Whether a removed view is still playing its removal. |
| `bridge._pendingLayoutCount()` | Views waiting for the next layout pass. |
| `bridge._flushLayout()` | Run the pending layout pass. |

Useful assertions for a retained screen: after an update, the refs you care
about are the same userdata as before (the node was patched, not rebuilt),
`_pendingLayoutCount()` is non-zero after a structural change, and frames read
after the update are final. See `tests/sector_chart.test.lua` and
`tests/auto_layout.test.lua`.

To check a running app, sample its retained refs from an `ns.async` loop and
count identity changes while real data streams in; that is how the Diskmap
overview's rebuild count was measured.
