# Reel

Motion pieces (showreels, promo videos) written as etlua templates and
rendered offline to H.264. A reel is a timeline of nodes whose attributes
and motion are functions of time; each frame is computed from `t` alone and
averaged over several sub-frames for real motion blur.

Reel is a separate module. The runtime never loads it, app bundles do not
ship it, and it uses none of the live animation engine (`withAnimation`,
`src/shared/motion.m`): that engine runs on the display clock, while a reel
must be able to render any instant exactly and repeatably.

| Piece | Where |
|---|---|
| Native canvas, images, text, SF Symbols, motion-blur accumulator, H.264 writer | `native/ReelNative.m` → `build/ReelNative.dylib` |
| Facade: load, stills, movies, captures | `Reel.lua` |
| Easing, springs (SwiftUI `response`/`dampingFraction`), pulses, beat grid | `reel/curves.lua` |
| Scene graph, attribute expressions, reduced-resolution layers | `reel/scene.lua` |
| Element vocabulary | `reel/elements.lua` |
| Motion modifiers and their sound events | `reel/motion.lua` |
| Window captures cut by view identifier | `reel/captures.lua` |
| `--screenshot` → window-only JPEG | `tools/import.lua` |
| Tests | `tests/reel.test.lua` |

The Diskmap reel (`reels/diskmap/`) is the reference user.

## Using it

A reel entry point adds the module to the Lua path, loads a template with
its data, and renders:

```lua
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local reel = Reel.load("reels/diskmap/views/Reel.etlua", {
	captures = Reel.captures("reels/diskmap/captures"),
	kicks = Reel.curves.every(0.5, 4, 20),
})
reel:still(8.9, "/tmp/still.png")              -- one motion-blurred frame
reel:movie("build/Showreel.mov", { from = 8, to = 10.3 })
for _, e in ipairs(reel.events) do print(e.time, e.kind) end  -- pops, slams, whooshes
```

```sh
./lua-objc reels/diskmap/init.lua stills /tmp 8.3,8.9,9.4
./lua-objc reels/diskmap/init.lua render /tmp/treemap.mov 8 10.3
```

## Templates

The root is `<Reel width height fps duration bpm subframes shutter
background>`. Scenes are partials, and the template data is also available
as `reel`, so `<%- partial("Treemap.etlua", reel) %>` hands a scene
everything. Repeated nodes use etlua loops, as in app views.

```xml
<Scene from="7.98" to="10.3">
  <Group x="960" y="612" scale="0.78" motion="punch(8), leave{at = 9.95, duration = 0.3, x = -2300}">
    <Window capture="treemap-dark" radius="24" shadow="1" motion="fadeIn(8.5, 0.12)">
      <% for i, tile in ipairs(captures:get("treemap-dark"):cells("treemap", 0)) do %>
      <Piece rect="#treemap/<%= tile.id %>" motion="pop(<%= stagger(8.75, i) %>, {turn = 0.25})" />
      <% end %>
    </Window>
  </Group>
  <Text style="head" text="Rings or rectangles." x="960" y="176" at="8.12" exit="9.72" />
</Scene>
```

Every node has `x`, `y`, `scale`, `rotation`, `alpha`, `anchor="x, y"`,
`from`, `to` (visible interval), `motion` and `resolution`. Children draw in
the node's own units, so pieces inside a `<Window>` or `<Frame>` are in
window points and land where they were on the page.

An attribute is a number, a colour (`#RRGGBB`, `#RRGGBBAA`) or a Lua
expression of `t`, compiled once: `x="520 + 180 * sin(t * 0.35)"`,
`alpha="0.22 + 0.06 * pulse(t, kicks, 0.18)"`. Expressions see the curves,
the beat grid (`beat`, `bar`), `sample(x, y)` of the nearest capture and the
reel data. The XML parser ends a tag at the first `>`, so write `&gt;` in
expressions.

| Element | Purpose |
|---|---|
| `Group`, `Scene` | Transform and visibility for children. |
| `Frame capture` | A capture's window-point space, centred on (x, y), without drawing it. |
| `Window capture radius shadow` | The whole capture, as a window. |
| `Piece rect outset key radius shadow` | Part of a capture: `rect="#view"`, `"#view/cell"` or `"x, y, w, h"`; `key="x, y"` keys out the colour at that point. |
| `Fill rect color outset` | Covers part of the window (`color="sample(x, y)"`). |
| `Sweep at duration` | A glint across the parent's bounds. |
| `Text style text align at stagger exit` | Words rising from behind their baseline mask. |
| `Backdrop color`, `Glow color radius`, `Vignette inner outer` | The stage. |
| `Palette name colors`, `Style name size weight color gradient tracking` | Definitions for text. |

Motion modifiers, composed left to right: `pop(at, {response, damping,
from, turn, fade, sound})`, `slam(at, {...})`, `enter{at, x, y}`,
`leave{at, duration, x, y, scale, curve, fade}`, `fadeIn(at, d)`,
`fadeOut(at, d)`, `punch(at)`, `spinOut(at, d, turns)`, `beat(hits)`.
`stagger(start, i, step)` spaces repeated nodes on the grid.

`resolution="0.25"` renders a full-frame subtree (lights, gradients) at a
quarter of the frame size and scales it up; the stage costs a few
milliseconds instead of half the frame.

## Captures

`Reel.captures(dir)` reads `<name>.jpg` (a 2× window-only capture) and
`<name>.layout.xml` (`--dump-layout` of the same window). The dump records
each view's `windowX`/`windowY` in top-left window points and lists treemap
cells, so pieces are cut by identifier and survive layout changes after a
fresh capture. `reels/diskmap/capture.sh` shows the capture step.
