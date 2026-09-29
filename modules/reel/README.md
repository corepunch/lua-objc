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
| Offscreen SceneKit: nodes posed per frame, Metal render to an image, projection | `native/scene.m` (included by `ReelNative.m`) |
| Facade: load, stills, movies, captures, toolkit exports | `Reel.lua` |
| Easing, springs (SwiftUI `response`/`damping`), pulses, keys, flips, beat grid | `reel/curves.lua` |
| The pen: transforms, shapes, sprites, type, symbols, chips, rings, bursts, glints | `reel/pen.lua` |
| Scene graph and attribute expressions | `reel/scene.lua` |
| `<SceneView>`: SceneKit records, surfaces, states, transitions from `t` | `reel/world.lua` |
| Vectors, orbits, dollies, smooth camera paths | `reel/space.lua` |
| Element vocabulary | `reel/elements.lua` |
| Motion presets and the sounds they imply | `reel/motion.lua` |
| Window captures cut by identifier, table row or treemap cell | `reel/captures.lua` |
| Offline mix: buses, sidechain, reverb, master | `reel/audio.lua` |
| Synth voices: pad, pluck, bass, drums, risers, whooshes, pops, bells | `reel/instruments.lua` |
| Tests | `tests/reel.test.lua`, `tests/reel_scene.test.lua` |

`reels/diskmap/` is the reference reel: a 30 s, 1080p piece in 11 scene
templates, one bespoke shot and a score.

## Rendering

```sh
./lua-objc reels/diskmap/init.lua stills /tmp 8.3,8.9,9.4
./lua-objc reels/diskmap/init.lua render build/Diskmap-Showreel.mov
make diskmap-reel-captures          # refresh captures after a UI change
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
| `Piece rect part outset key radius shadow` | Part of a capture: `rect="#view"` (any identifier, even `#task/2`), `"#view/row/N"`, `"#view/cell"` or `"x, y, w, h"`; `part` narrows it; `key="x, y"` keys out the colour there. |
| `Image src density width height radius shadow` | An image file with no layout (a simulator screenshot) at its top-left corner; `density` is pixels per point. |
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
| `Palette name colors`, `Style name size weight color gradient tracking kern digits design` | Definitions for type. |
| `Cue sound at until` | A sound event with no picture. |
| `Draw with` | A bespoke shot from `data.shots`. |

**Motion presets**, composed left to right: `pop(at, {response, damping,
from, turn, fade, sound})`, `slam(at, {from, drop, ...})`, `enter{at, x, y,
fade, sound}`, `leave{at, duration, x, y, scale, curve, fade, stay, sound}`,
`fadeIn(at, d)`, `fadeOut(at, d)`, `punch(at)`, `spinOut(at, d, turns)`,
`beat(hits)`. `pop` and `slam` imply their sound; `enter` and `leave` sound
only when given one; `sound = false` silences a duplicate.

## SceneKit

`<SceneView>` puts a SceneKit scene in a reel, rendered offscreen through
Metal at its on-screen pixel size, 4x multisampled and motion blurred like
everything else. Its records are the live
[SceneView](../../docs/PROJECT_REFERENCE.md)'s: `<Node>` (a `model` file or
a `geometry`), `<Camera>` and `<Light>`, with `position`, `rotation`
(degrees), `scale`, `spin`, `bob`, `transition`, `lookAt` and the rest. An
app's own scene templates therefore render in a reel unchanged: Coin
Quest's prefabs are partials of the promo reel. What the live view runs on
the display clock is a function of `t` here, so any instant renders exactly:

- every attribute may be an expression of `t`, and vectors are `"x y z"`
  or an expression returning `{x, y, z}`;
- `spin` and `bob` turn and float the content from `t`;
- `from` and `to` put a record on and off stage, playing its `transition`
  (`pop`, `rise`, `fade`) with the live view's curves;
- `states="poses(t)"` is the live view's `nodeStates`: poses
  `{id, x, y, z, yaw, pitch, roll, scale, opacity, hidden}` that override the
  template for the frame, which is how a game's own simulation drives a reel.

```xml
<SceneView environment="studio" background="#0B0B0F" states="quest(t)">
  <Camera position="path(t, cameraKeys)" lookAt="path(t, targetKeys)" fieldOfView="track(t, lensKeys)"
          focusDistance="3.2" fStop="2.8" />
  <Light type="directional" rotation="-50 30 0" intensity="1400" castsShadow="true" />
  <Node id="phone" geometry="slab" width="0.72" height="1.5" length="0.08" cornerRadius="0.11" chamfer="0.025"
        color="#2A2A2E" metalness="0.9" roughness="0.25" rotation="0, 30 * sin(t), 0">
    <Node geometry="plane" width="0.68" height="1.46" cornerRadius="0.09" position="0 0 0.041" roughness="0.08">
      <Surface width="393" height="852">
        <Window capture="todo-phone" />
        <Text style="head" text="Hello" x="196" y="400" at="1.2" />
      </Surface>
    </Node>
  </Node>
</SceneView>
```

Beyond the live vocabulary, for product shots:

| Attribute or record | Purpose |
|---|---|
| `geometry="slab"` `width height length cornerRadius chamfer` | A rounded rectangle extruded `length` deep with rounded edges: a device body. |
| `metalness roughness clearcoat clearcoatRoughness emission lighting` | Physically based material (`lighting` is `physical`, `blinn`, `lambert` or `constant`). |
| `transparency blend order doubleSided writesDepth readsDepth` | Glass, glows and sorting. |
| `image` (`imageSlot`) | A capture, piece or image on the node's geometry, self-lit (`emission`) by default. |
| `<Surface width height density slot background>` | The node's screen, drawn every frame by ordinary reel elements in points, so app content animates on the glass. A surface may hold a `<SceneView>`: a game on a phone. |
| Camera `focusDistance fStop bloom exposure vignetting hdr roll` | Lens: depth of field, bloom and a roll about the view axis. |
| Light `temperature shadowScale shadowMapSize spotInner spotOuter` | Physical light and shadow control. |
| SceneView `environment environmentIntensity` | Image-based lighting and reflections from an equirectangular image (an expression). |
| SceneView `camera` | The camera record to look through (an id, or an expression that cuts). |

`project('viewId', {x, y, z})` in a later attribute returns where a world
point landed in that view this frame, so crisp reel type can follow a 3-D
object. `reel/space.lua` supplies the camera helpers every attribute sees:
`vec`, `add3`, `sub3`, `scale3`, `lerp3`, `length3`, `normalize3`,
`orbit(target, distance, yaw, pitch)`, `dolly(from, target, distance)`,
`fill(height, fieldOfView)`, `rotate(v, rotation)` and
`transform(point, position, rotation, scale)` (SceneKit's euler order, to
find a point on a device's screen in the world), `path(t, {{t0, {x, y, z}}, …})` (smooth
through every key, easing out of the first and into the last; `hold = true`
stops dead) and `track(t, keys)` for single values.

## Bespoke shots

A shot is `shots.name(pen, t, node)`, or `{ setup = fn(node, context),
draw = fn(pen, t, node) }` when it uses captures: `setup` runs while the reel
loads, so a missing capture or view fails the load instead of a render
minutes in. The pen draws in the node's units and tracks opacity and
on-screen scale, so shadows and glints keep their screen size:

```lua
shots.wall = {}
function shots.wall.setup(node, context)
	node.pages = {}
	for i, name in ipairs(context.data.wallPages) do node.pages[i] = context.captures:get(name) end
end
function shots.wall.draw(pen, t, node)
	for i, page in ipairs(node.pages) do
		pen:place({ x = …, y = …, scale = …, rotation = …, alpha = …, anchor = { 720, 450 } }, function()
			pen:sprite(page:piece("window", { downsample = 0.3 }), { radius = 24, shadow = 0.8 })
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

`Reel.captures(dir, hint)` reads what `lua-objc --capture=<dir>/<name>`, or
`capture.shot` in a `--capture-plan`, writes: `<name>.png`, the window's
content at backing scale, and `<name>.layout.xml`, its layout dump. The
layout's `scale` maps points to pixels; each view's `window` rectangle is
`"x y width height"` in top-left window points; treemap cells are listed and
table rows belong to their nearest identified view. Pieces are cut by
identifier and survive layout changes after a fresh capture. Captures are
generated, so reels keep them out of git.

Anything a reel expects and a capture lacks is an error naming it, raised
while the reel loads wherever the template or a shot's `setup` asks for it: a
missing capture file (with `hint` saying how to make it), an unknown view,
row or treemap cell, a view with no rows or cells, a layout without a scale,
or an image that is not the layout's root at that scale. `row(view, n)`,
`rows(view)`, `cells(view, depth)` and `rect(spec)` never return an empty
answer.
