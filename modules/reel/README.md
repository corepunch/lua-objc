# Reel

Motion pieces (showreels, promo videos) written as etlua templates and
rendered offline to H.264 with a synthesised score. A reel is a timeline of
nodes whose attributes and motion are functions of time; each frame is
computed from `t` alone and averaged over sub-frames for real motion blur.

The toolkit has two layers over the same primitives:

- **Short syntax** for the common 90 %: elements, attributes that are Lua
  expressions of `t`, motion presets (`motion="pop(8.75)"`), `stagger`,
  `clip`, per-frame `<Let>` variables and pieces cut from app captures by
  view identifier.
- **Bespoke shots** with full control: `<Draw with="dive"/>` hands a Lua
  function the pen, the same drawing toolkit every element uses, placed and
  animated like any other node.

Reel is a separate module. The runtime never loads it, app bundles do not
ship it, and it uses none of the live animation engine (`withAnimation`,
`src/shared/motion.m`): that engine runs on the display clock, while a reel
must render any instant exactly and repeatably.

| Piece | Where |
|---|---|
| Canvas, images, glyph text, SF Symbols, motion blur, H.264 writer and reader, WAV | `native/ReelNative.m` → `build/ReelNative.dylib` |
| Facade: load, stills, movies, captures, toolkit exports | `Reel.lua` |
| Easing, springs (SwiftUI `response`/`damping`), pulses, keys, flips, beat grid | `reel/curves.lua` |
| The pen: transforms, shapes, sprites, type, symbols, chips, rings, bursts, glints | `reel/pen.lua` |
| Scene graph and attribute expressions | `reel/scene.lua` |
| Element vocabulary | `reel/elements.lua` |
| Motion presets and the sounds they imply | `reel/motion.lua` |
| Window captures cut by identifier, table row or treemap cell | `reel/captures.lua` |
| Offline mix: buses, sidechain, reverb, master | `reel/audio.lua` |
| Synth voices: pad, pluck, bass, drums, risers, whooshes, pops, bells | `reel/instruments.lua` |
| `--screenshot` → window-only JPEG | `tools/import.lua` |
| Tests | `tests/reel.test.lua` |

`reels/diskmap/` is the reference reel: a 30 s, 1080p piece in 11 scene
templates, one bespoke shot and a score.

## Rendering

```sh
./lua-objc reels/diskmap/init.lua stills /tmp 8.3,8.9,9.4
./lua-objc reels/diskmap/init.lua render build/Diskmap-Showreel.mov
reels/diskmap/capture.sh            # refresh captures after a UI change
```

```lua
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local reel = Reel.load("reels/diskmap/views/Reel.etlua", {
	captures = Reel.captures("reels/diskmap/captures"),
	kicks = Reel.curves.every(0.5, 4, 20),
	shots = require("shots"),
})
reel:still(8.9, "/tmp/still.png")
reel:movie("build/Showreel.mov", { audio = "/tmp/score.wav" })
for _, e in ipairs(reel.events) do print(e.time, e.kind) end -- pops, slams, whooshes, cues
```

## Short syntax

The root is `<Reel width height fps duration bpm subframes shutter
background>`. Scenes are partials; the template data is also `reel`, so
`<%- partial("Treemap.etlua", reel) %>` hands a scene everything. Repeated
nodes use etlua loops.

```xml
<Scene from="7.98" to="10.3">
  <Group x="960" y="612" scale="0.78" motion="punch(8), leave{at = 9.95, duration = 0.3, x = -2300}">
    <Window capture="treemap-dark" radius="24" shadow="1" motion="fadeIn(8.5, 0.12)">
      <Group stagger="0.125">
        <% for _, tile in ipairs(captures:get("treemap-dark"):cells("treemap", 0)) do %>
        <Piece rect="#treemap/<%= tile.id %>" motion="pop(8.75, {turn = 0.25})" />
        <% end %>
      </Group>
    </Window>
  </Group>
  <Text style="head" text="Rings or rectangles." x="960" y="176" at="8.12" exit="9.72" />
</Scene>
```

**Every node** takes `x`, `y`, `scale`, `sx`, `sy`, `rotation`, `alpha`,
`anchor="x, y"` (or animated `anchorX`, `anchorY`), `from`, `to` (visible
interval), `clip` (a shape), `motion`, `stagger` (each child runs that much
later than the previous one, events included), `resolution` (render a soft
full-frame subtree at a fraction of the size) and `capture`. Children draw
in the node's own units: inside a `<Window>` or `<Frame>` they are in
window points and land where they were on the page.

**Attributes** are numbers, colours (`#RRGGBB`, `#RRGGBBAA`) or Lua
expressions of `t`, compiled once: `x="520 + 180 * sin(t * 0.35)"`. They
see the curves and easings by name (`outQuart(progress(t, 3, 3.85))`,
`spring(t - 4, 1 / 1.5, 0.55)`, `mixScale`, `pulse`, `keys`, `flip`,
`shakeX`), shapes (`rect`, `roundedRect`, `circle`, `sector`, `without`),
`rgb(0xC65BF0, 0.5)`, `sample(x, y)` of the nearest capture, `step(x)`, the
reel data and every `<Let>`. The XML parser ends a tag at the first `>`, so
use `step()` or `&gt;` for comparisons.

| Element | Purpose |
|---|---|
| `Group`, `Scene` | Transform, visibility and clip for children. |
| `Let name value` | A per-frame variable for later attributes. |
| `Frame capture` | A capture's window-point space, centred on (x, y), not drawn. |
| `Window capture radius shadow downsample` | The whole capture as a window. |
| `Piece rect part outset key radius shadow` | Part of a capture: `rect="#view"`, `"#view/row/N"`, `"#view/cell"` or `"x, y, w, h"`; `part` narrows it; `key="x, y"` keys out the colour there. |
| `Fill rect color outset` | Covers part of the window (`color="sample(x, y)"`). |
| `Rect width height radius color shadowBlur shadowY shadowColor` | A rectangle from its position. |
| `Circle radius color stroke shadowBlur` | A disc or ring centred on its position. |
| `Symbol name size color`, `Chip symbol color size` | An SF Symbol; a badge with a white symbol. |
| `Ring radius width sweep turn segments track` | A segmented donut drawn on from 12 o'clock. |
| `Burst at colors count speed seed` | Particles thrown from its position. |
| `Sweep at duration` | A glint across the parent's bounds. |
| `Text style text align at stagger exit` | Words rising from behind their baseline mask. |
| `Slam style text at="t1, t2…" styleN` | Words landing from large, each on its own hit. |
| `Counter value format final unit style unitStyle` | Digits ticking in fixed slots with a still unit. |
| `Backdrop color`, `Glow color radius colors locations`, `Vignette inner outer` | The stage. |
| `Palette name colors`, `Style name size weight color gradient tracking kern digits` | Definitions for type. |
| `Cue sound at until` | A sound event with no picture. |
| `Draw with` | A bespoke shot from `data.shots`. |

**Motion presets**, composed left to right: `pop(at, {response, damping,
from, turn, fade, sound})`, `slam(at, {from, drop, ...})`, `enter{at, x, y,
fade, sound}`, `leave{at, duration, x, y, scale, curve, fade, stay, sound}`,
`fadeIn(at, d)`, `fadeOut(at, d)`, `punch(at)`, `spinOut(at, d, turns)`,
`beat(hits)`. `pop` and `slam` imply their sound; `enter` and `leave` sound
only when given one; `sound = false` silences a duplicate.

## Bespoke shots

A shot is `shots.name(pen, t, node)`. The pen draws in the node's units and
tracks opacity and on-screen scale, so shadows and glints keep their screen
size:

```lua
function shots.wall(pen, t, node)
	local captures = node.context.captures
	for i, name in ipairs(node.context.data.wallPages) do
		pen:place({ x = …, y = …, scale = …, rotation = …, alpha = …, anchor = { 720, 450 } }, function()
			pen:sprite(captures:get(name):piece("window", { downsample = 0.3 }), { radius = 24, shadow = 0.8 })
		end)
	end
end
```

Pen: `place`, `save`/`restore`, `translate`, `rotate`, `scale`, `fade`,
`clip(shape)`, `fill(shape, colour)`, `stroke`, `rect`, `shadow`, `glow`,
`radial`, `linear`, `sprite(sprite, {radius, shadow, clip})`,
`text(text, style, x, baseline, align)`, `run`/`word`, `symbol`, `chip`,
`ring`, `burst`, `sweep`. `Reel.Shape`, `Reel.rgb` and `Reel.curves` are the
same helpers attributes use.

## Scores

`Reel.audio.new(duration, sampleRate)` is a mix with dry, sidechained and
reverb-send buses; `Reel.instruments` are single notes and hits (`pad`,
`pluck`, `bass`, `kick`, `clap`, `hat`, `crash`, `roll`, `riser`, `whoosh`,
`slam`, `boom`, `blip`, `tone`, `bell`). A score sequences them from
`reel.events`, the pops, slams and cues the picture declares, plus its own
musical data, then `mix:master{kicks, gain}` returns two sample arrays for
`Reel.writeWav`. See `reels/diskmap/Score.lua`.

## Captures

`Reel.captures(dir)` reads `<name>.jpg` (a 2× window-only capture) and
`<name>.layout.xml` (`--dump-layout` of the same window). The dump records
each view's `window` rectangle (`"x y width height"` in top-left window
points) and lists treemap cells; table rows belong to their nearest
identified view. Pieces are cut by identifier and survive layout changes after a fresh capture.
