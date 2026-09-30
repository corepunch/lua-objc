# Making 3-D reels

A practical guide to building a promo film with Reel's SceneKit layer,
distilled from making `reels/promo` (the lua-objc promo). It covers the
pipeline from app captures to a finished movie, and the traps found by trial
and error, each with its fix and the reason. The element and attribute
reference is [modules/reel/README.md](../modules/reel/README.md); the
reference reel is [reels/promo](../reels/promo/README.md).

```sh
make promo-reel                                      # capture if needed, then render
./lua-objc reels/promo/capture.lua mac iphone studio # recapture (any subset)
REEL_SUBFRAMES=1 ./lua-objc reels/promo/init.lua stills /tmp 4.6,7.2   # fast look
./lua-objc reels/promo/init.lua render /tmp/part.mov 13 17             # a span, with music
```

## 1. Shape of a reel

```
reels/<name>/
  init.lua           data for the templates, render modes, music data
  views/Reel.etlua   styles, stage, layer order (World, then 2-D type)
  views/World.etlua  one <SceneView>: camera, lights, device prefabs
  views/devices/     SceneKit prefabs (phone, pad, display, window)
  views/Type.etlua   everything written on the film
  Choreography.lua   the camera and every device as functions of t
  Motion.lua         component motion on screens (optional)
  Regions.lua        components found in screenshots (optional)
  shots.lua          <Draw with="…"> shots
  Score.lua          music from the same timeline
  capture.lua        capture pipeline; captures/ is generated, not committed
```

Everything is a pure function of `t`. Stills, motion-blur sub-frames and
the movie must agree, so nothing may depend on the previous frame, a
running clock, SceneKit actions, or state mutated during drawing.

## 2. Real content: the capture pipeline

**Show real apps, captured by the pipeline, never mock-ups.**

- **Mac windows:** `lua-objc --capture=<prefix> --width --height app/init.lua`
  writes the PNG *and* a layout dump, so pieces can be cut by view
  identifier (`<Piece rect="#card/income">`).
- **iPhone:** the UIKit host streamed by the packager (`--root <dir>
  --entry <app>`), launched with `SIMCTL_CHILD_LUA_OBJC_APP`, captured with
  `xcrun simctl io <udid> screenshot`. The Simulator app never has to open.
- **iPad:** a bundled app (`make ipad-simulator APP=<slug> APP_DIR=<dir>`
  with `OVERLAY=` folders for extra files), installed and launched with
  `simctl`.
- **Lua Studio mid-session:** `LUA_STUDIO_SHOWCASE=<file>` opens a bundled
  project with a prepared conversation (`reels/promo/Conversation.lua`
  writes it from the edit patches).

**Before/after states are real code.** Keep the app in the repository in its
final state; store each agent edit as a unified diff; rebuild version k by
reverse-applying edits k+1…n in a *root of symbolic links* to the checkout
with a copied app folder (module paths like `demo.todo.Model` must keep
resolving). States reached by *using* the app (a task checked, a filter
chosen) are the app with its sample data changed by exact text
replacements. Keep states consistent along the story: a task checked in one
scene stays checked in the next. Test that every patch and replacement still
applies (`tests/promo_reel.test.lua`), or the edits rot silently.

**Capture hygiene:**

| Trap | Fix |
|---|---|
| Legacy scroll bars in Mac captures (system setting "always show") | Pass `-AppleShowScrollBars WhenScrolling` after the app path (argument domain) |
| Simulator status bar shows the real time and battery | `xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging --batteryLevel 100 …` |
| iPad status bar shows "◀ Lua Studio" / "◀ ledger" | The previous app launched it; `simctl terminate` the other bundle before launching |
| Captures differ run to run (network data) | Give the app an offline `--showcase` data mode (`apps/weather --showcase`) |
| `simctl` fails with CoreSimulator connection errors in a sandboxed shell | Run it with elevated permissions; the runtime is not missing |
| Root folders reused for two variants | Give each variant its own root folder; a later step (the iPad bundle overlay) still reads the version roots |
| `diff` returns failure in tests on this Mac | `/usr/local/bin/diff` is a broken Intel binary; call `/usr/bin/diff` |

## 3. Cut screens into components

**Never show a screenshot whole and still.** Cut it into rows, cards,
controls, bubbles and lines, and move those.

- Mac captures have layout dumps: cut by identifier. Give views meaningful
  ids (`task/2`, `card/income`, `forecast/3`); identifiers containing `/`
  cut as whole views.
- Simulator screenshots have no layout: find components in the pixels when
  the reel loads (`reels/promo/Regions.lua`). Recaptures then need no
  re-measuring. The techniques that worked:
  - **Row dividers:** a row of one light grey across the column *with white
    just above and below it*. A card's fill is also grey across the column,
    for many rows.
  - **Blocks** (cards, segmented controls): runs of non-white rows across the
    control's *width*. One column is not enough: a selected segment is white.
  - **Row height:** the smallest gap between dividers. A gap much taller
    than a row holds a section label.
  - **Chat pieces:** bands of non-white rows. Classify them by what the
    middle row holds: a *run* of accent blue is a user bubble (the agent's
    sparkle icon is blue too, but small), card grey is a card, otherwise
    text. Tighten each band horizontally to its content, so a bubble is cut
    at its own edges.
  - **Measuring once by hand:** scan pixels with a small script
    (`image:pixel(x, y)` in points) rather than guessing from a resized
    screenshot.
- Take identity from the app's model, not the pixels: which task a row is
  comes from `demo.todo.Model`'s own ordering for that state
  (`reels/promo/Todo.lua`).
- Write a debug overlay (the regions stroked over the screenshots) and look
  at it for every state before animating anything.

## 4. Component motion that reads well

**Matched-geometry morph between two states** (`Motion.lua`):

- Rows present in both states slide to their new place on a spring
  (response ≈ 0.5, damping ≈ 0.75), staggered 30–40 ms top to bottom, and are
  lifted while moving: slight scale, soft shadow, an **opaque rounded backing**.
- Draw moving rows **above** still ones. Without the backing and the
  ordering, rows crossing each other mix their text into mush.
- **Cross-fade only if the face changed** (compare a few pixels of the two
  crops). Fading identical faces doubles them mid-flight. A row that stays
  put but changes (a checkbox, a percentage) gets a small scale bump instead.
- New components pop in on a springier curve after the rows start to make
  room. Removed ones fall and fade *within the screen*.

**Other rules:**

- **Nothing leaves the frame.** Components assemble *in place* (rise from
  just below, grow, a slight turn), never from beyond the screen's edge. A
  bubble flying from the composer to the chat only takes off once the camera
  shows *both* ends of its flight. A device leaving the scene recedes into
  depth and fades; it never slides out. Entrances from outside are
  acceptable; exits are not.
- **Masks belong to their element.** A reveal mask (diff lines wiping in)
  must only draw while its card is shown, or it leaves grey bars behind.
- **Clear only what you redraw.** Painting over a region of a capture to
  redraw it as pieces must stop exactly at its edge. Measure the next
  element's top (suggestion chips at y 932) and stop above it.
- **Typing:** reveal the capture's own draft text from behind a patch of the
  field's colour (sample it: glass fields are `#FDFDFD`, not white), limited
  to the text's extent so buttons beside it stay visible.
- **Taps:** a translucent finger dot that arrives, presses (shrinks) and
  lifts with a spreading ring, aimed at a component's rect, not at hand-typed
  coordinates.
- **Captions** over busy screens: a dark rounded pill at the foot of the
  frame that springs up on the beat. Free-floating white words collide with
  screens.
- **Faked UI** (a feature that isn't shipping yet) is drawn with the pen in
  the product's style, and the reel's README says it is faked.
- **A chat that scrolls:** capture it opened at its latest turn, as the app
  shows it. On a send, the previous capture's conversation slides up by the
  distance between the two captures' shared turn (`Regions.scroll`) while the
  new bubble flies in; only the new exchange is cut into pieces.
- **Code on screen** comes from the edit's own patch (`Conversation.files`),
  never retyped, so the film cannot show code the app does not have.

## 5. SceneKit in a reel

**Rendering facts learned the hard way:**

- **Flush before every render.** A reel has no run loop, so SceneKit's
  implicit transaction never commits: poses silently stay at the first
  frame's. `native/scene.m` calls `[SCNTransaction flush]` in `render`.
- **Euler order:** SceneKit turns a node about x (pitch), then y (yaw), then
  z (roll), in the parent's axes (verified against `convertPosition`; the
  docs' wording suggests otherwise). `Space.rotate` / `Space.transform`
  follow it. Use them to find a point on a device's screen in the world.
- **Screens are emissive.** Put the picture in `emission` with a **black
  diffuse**. A white default diffuse, lit, adds to the emission and washes
  the screen out to white. Physically based lighting with low roughness adds
  a faint glass reflection on top.
- **Model devices from their published dimensions** and check them from
  the front first: a display is judged by its border and its stand. The
  promo's Studio Display is centred glass with an even border around a 16:9
  screen, and a stand that leans back from the panel and folds forward into
  the foot; `tests/promo_reel.test.lua` keeps the proportions.
- **Device bodies:** `geometry="slab"` (a rounded rectangle extruded with a
  quarter-circle chamfer) reads as a real body. Put black clearcoat glass in
  front, the screen plane a hair in front of that, and a camera plateau with
  lenses on the back.
- **A landscape phone is built lying down,** not a portrait phone rolled
  inside another node: its screen's surface is then 874 × 402 and its content
  needs no rotating.
- **Lighting:** an equirectangular studio environment drawn with the pen
  (`Stage.lua`: dark room, soft key above, strip lights) gives metal and
  glass something to reflect. Two spot lights that follow the camera add rim
  light. Without them titanium reads as a black silhouette on a dark stage.
- **Transparent planes** (words in the air) use the `diffuse` slot with
  `lighting="constant"` and a clear surface background. Emission ignores
  alpha.
- **Depth of field** needs `focusDistance` (the eye-to-target distance) and a
  low f-stop (≈1.4–2.8). Scene units are treated as metres, so small scenes
  need wide apertures.

**Surfaces** (live 2-D content on a node):

- A surface is redrawn every sub-frame, so it must be cheap. Surfaces off
  screen are skipped (bounding box projected with `scene:extent`), and each
  draws at the density its on-screen size needs (quantised levels, never
  above its own `density`).
- A surface uploads straight into a Metal texture the node keeps, mipmapped
  on the GPU. Going through a CGImage made SceneKit copy and re-premultiply
  every frame on the CPU.
- A surface may hold a `<SceneView>`: a game running on a phone.

**An app's own scene template renders unchanged.** Coin Quest's
`Stage.etlua` and prefabs go into the reel as partials. Drive them with
`states=` (the reel's `nodeStates`) from a deterministic replay of the game's
own model (`CoinQuest.lua`: fixed 240 Hz steps, scripted pad, recorded
poses, interpolated per sub-frame; yaw snaps rather than interpolating
through ±180°). A camera state may carry `lookAt` and `fieldOfView`, so the
reel films the game through the game's own camera record. To add attributes
to a partial's root element, edit the rendered string
(`stage:gsub("<SceneView ", '<SceneView states="…" ', 1)`).

## 6. Camera and choreography

**Keyed paths:** use `path(t, keys)` / `track(t, keys)`. They are Hermite
curves with Catmull-Rom tangents, smooth through keys and easing at the ends.

- **Holds:** a key equal to its neighbour stops dead (`reel/space.lua` does
  this now). Before that fix, two equal keys still drifted, because the
  outer key's tangent came from its other neighbour. That is how a "held"
  iPad wandered 0.9 units. `hold = true` forces a stop.
- **Frame from the geometry, not by eye.** Compute framings from device
  poses (`onPad(u, v, distance)`: a point in screen points, seen square-on
  from a distance). Hand-typed eye/target pairs for close-ups miss.
- **Slow down.** Fewer moves, holds while a screen changes, and a move only
  once the thing being read has finished (a diff done cascading before the
  camera turns to the phone). **Cause and effect in one shot:** a held
  two-shot of the chat beside the phone beats cutting back and forth.
- **Composition:** leave the left third clear where words go, and put the
  subject right of centre. Check every text frame for collisions with
  devices, especially the end card.
- **Exact hand-offs** are computed, and tested:
  - **Swap one object for another** (a portrait phone rolled 90° into the
    landscape game phone): same position and same attitude. Keep pitch and
    yaw at 0 at the swap, since rolls do not commute with them.
  - **Push into a screen and cut into its world:** at the cut, the camera
    is square to the screen at the distance where the screen's height fills
    the frame (`h / 2 / tan(fov / 2)`), with the same vertical field of view
    the inner scene's camera uses. The picture on the glass and the full
    frame are then identical. A horizontal-axis lens breaks this, so use
    vertical for both.
- Put every event on the beat grid (120 BPM: 0.5 s) and test that it is.

## 7. Music and timing

`Score.lua` sequences the synth instruments from the same timeline as the
picture:

- a pop on every change on a screen, and a softer one as its new parts land
- a tick per tap and per typed character
- chimes on sends
- slams from the reel's own `<Slam>` events
- coins from the replay's events
- crashes and booms on the drops, a breath (gain dip) just before them
- risers into the drops and the logo

When the timeline changes, move the music with it. The music data in
`init.lua` reads `C.SHOT`.

## 8. etlua and XML traps

| Trap | Symptom | Fix |
|---|---|---|
| An apostrophe in a Lua line comment inside `<% %>` | `failed to find string close` | etlua scans Lua strings to find `%>`; rephrase (`--[[ ]]` block comments are fine) |
| `<%= %>` escapes HTML | `&lt;` appears literally in text | Don't pre-escape values you print with `<%= %>` |
| `>` inside an attribute expression | The tag ends early | Use `step(x)` or `&gt;` |
| `position="a, b, c"` as an expression | Silently became `{a, a, a}` | Vectors take three values or a `{x, y, z}` table; the reel accepts both now |
| A function returning several values used as a vector (`select(2, …)`) | Wrong vector | Wrap in parentheses: `(select(2, f()))` |
| An element attribute named `scale` for pixel density | The node itself was scaled | `scale` is every node's transform; use `density` |
| Partial paths | Resolve relative to the calling template | Pass `root` in the data and use absolute paths for another app's templates |

## 9. Performance

Profile before optimising:
`sample $(pgrep -x lua-objc) 6 -file /tmp/s.txt`, then sum the functions
on the main thread. The promo went from 828 s to about 200 s for 900 frames:

1. **Decode images once.** ImageIO returns lazily decoded images:
   `CGContextDrawImage` inflated the PNG and colour-matched it from 16-bit on
   every draw (74% of the time). `native.image` now decodes into the
   canvas's own format at load.
2. **Upload surfaces directly to Metal** (above).
3. **Draw soft full-frame layers at a fraction of the resolution**
   (`resolution="0.25"`): vignettes, glows, wallpapers.
4. **Skip off-screen surfaces and draw far ones coarsely.**

H.264 encoding was under 1%. Writing PNGs or using ffmpeg would not have
helped: the movie writer takes canvases straight into AVFoundation.

**Sub-frames:** 5 are enough for most motion; fast moves strobe (discrete
copies). `subframes` can be an expression of `t`, adding samples only where
the motion is fast:
`subframes="5 + 4 * step(t - 4.95) * step(6.0 - t)"`.

## 10. Review loop

- **Iterate on stills without motion blur:**
  `REEL_SUBFRAMES=1 … stills <dir> <times>`, about 0.1–0.5 s each.
- **Contact sheets:** render 25–35 stills across the film and tile them
  (a ten-line Lua script with `native.canvas` and `canvas:image`). One image
  shows pacing, composition and collisions at once.
- **Check the movie, not only stills:** read frames back with
  `native.frames(path)` and tile the ones around each transition. Motion blur
  and timing problems (a morph during a camera move, a bubble smearing off
  screen) only show there.
- **Check each hand-off with a pair of frames just before and after it.**
- **Before calling it done,** look for:
  - text colliding with devices
  - anything cropped by an overlay
  - anything leaving the frame
  - moves that start before the previous action finished
  - holds that drift
  - captures showing stale layouts after the app changed (recapture and
    re-measure)
