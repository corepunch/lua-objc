# SceneKit scenes and games

`<SceneView>` puts a SceneKit scene in an etlua template. The scene graph is
described with `<Node>`, `<Camera>` and `<Light>` records, reconciles by id
like any retained template, and moves every frame from game state without
re-rendering. This guide covers the tag, the reconciliation and pose
contracts, and the architecture a game built on it should follow.
[`apps/coin-quest`](https://github.com/corepunch/lua-objc/tree/main/apps/coin-quest)
is the reference game.

| Piece | Where |
|---|---|
| Native view, reconciliation, poses, frame and key hooks | `src/shared/scene_view.m` (`LuaSceneView`) |
| Tuning constants (lens, lights, shadows, transitions) | `kScene*` in `src/main.m` |
| Lua constructor and `sceneGraph` | `AppKit.SceneView`, `AppKit.sceneGraph` in `lua/embedded/AppKit.lua` |
| XML tags | `SceneView`, `Node`, `Camera`, `Light` in `lua/ui/xml.lua` |
| Tests | `tests/scene_view.test.lua`, `tests/coin_quest.test.lua` |
| Reference game | `apps/coin-quest/` and its `README.md` |

`SceneView` is AppKit only; UIKit has no counterpart yet.

## The tag

```xml
<SceneView id="scene" background="#a9dcf5" onKey="key" onFrame="frame">
	<Camera id="camera" position="5 12 10" lookAt="5 0 3" fieldOfView="52" fieldOfViewAxis="horizontal" />
	<Light id="sun" type="directional" rotation="-58 38 0" castsShadow="true" />
	<Light type="ambient" intensity="480" />
	<Node id="ground" geometry="box" width="10" height="1" length="6" color="systemGreen" position="5 -0.5 3" />
	<% for _, coin in ipairs(coins) do -%>
	<Node id="<%= coin.id %>" model="apps/game/assets/coin-gold.obj" position="<%= coin.x %> 0.15 <%= coin.z %>"
	      spin="150" bob="0.08" transition="pop" />
	<% end -%>
	<Node id="saw" position="2 0 1">
		<Node model="apps/game/assets/saw.obj" position="0 0.42 0" spin="0 0 -540" />
	</Node>
</SceneView>
```

Like SwiftUI's `SceneView`, the view has no intrinsic size and fills its
proposal. It takes the keyboard when it appears.

| Tag | Attributes |
|---|---|
| `SceneView` | `background` (semantic name or `#rrggbb`), `onKey`, `onFrame`, `onSwipe`, `onTap`, `virtualGamepad`, `showsStatistics`, plus layout attributes |
| `Node` | `id`, `model` or `geometry`, `width`, `height`, `length`, `radius`, `chamfer`, `color`, `position`, `rotation`, `scale`, `hidden`, `opacity`, `castsShadow`, `spin`, `bob`, `bobPeriod`, `transition`, `lookAt` |
| `Camera` | `id`, `position`, `rotation`, `lookAt`, `fieldOfView`, `fieldOfViewAxis`, `zNear`, `zFar`, `orthographicScale` |
| `Light` | `id`, `type`, `position`, `rotation`, `lookAt`, `intensity`, `color`, `castsShadow`, `shadowRadius`, `shadowOpacity` |

- **Units.** Positions and sizes are scene units; `rotation` is `"x y z"` in
  degrees; `position` and `scale` take `"x y z"` or one number for all three.
- **Content.** `model` loads a file SceneKit imports: OBJ with its MTL and
  textures, DAE, USDZ or SCN. Paths are relative to the working directory,
  like image paths; textures named in an MTL resolve next to the model. Each
  file loads once and is cloned per node, sharing geometry and materials.
  `geometry` is `box`, `sphere`, `cylinder`, `cone`, `plane` or `floor`,
  filled with `color`.
- **Hierarchy.** Child records hang from their node and move with it.
- **Behaviours.** `spin` turns the node's content at degrees per second:
  about the vertical axis for one number, per axis for `"x y z"`. `bob`
  floats it up and down by that many units every `bobPeriod` seconds. Both
  run natively as `SCNAction`s; no Lua runs per frame for a coin turning in
  place.
- **Transitions.** `transition` is `pop`, `rise` or `fade`. It plays when a
  node is inserted after the first render or removed. The first render shows
  the scene as it is, like a view appearing.
- **Camera.** The first `Camera` is the point of view. The field of view is
  vertical by default; `fieldOfViewAxis="horizontal"` keeps the scene's
  width framed however the view is shaped.
- **Lights.** `type` is `directional` (default), `ambient`, `omni` or
  `spot`. Only lights with `castsShadow="true"` cast shadows.
- **Aiming.** `lookAt` turns a node (a camera, usually) to face a point and
  keeps it upright, whatever it was turned to before.

## Reconciliation

Render the scene from a retained template (`ui/template.lua`). When it
renders again, the XML reconciler hands the new records to the view through
the schema's `updateRecords` hook, and the view reconciles them by id:

- a node whose id and kind still match keeps its `SCNNode`, pose and running
  behaviours;
- only attributes whose value changed are applied, so an unchanged
  `position` never snaps a moving node back to where the template put it;
- a model, geometry or color change rebuilds only that node's content;
- a node missing from the records leaves with its `transition`, and only the
  topmost removed node plays it;
- a record without an id is keyed by its position under its parent;
- a node moved under a different parent is rebuilt.

That last rule is how a game swaps levels: hang everything a level owns from
`<Node id="level-<%= level %>">`, and loading another level replaces the
whole subtree while the camera and lights stay.

An unreadable model, an unknown geometry or a duplicate id raises an error
naming the node, and a non-record child of `SceneView` is refused.

## Poses

Structure comes from the template; motion does not. Assign poses every frame:

```lua
refs.scene.nodeStates = {
	{id = "player", x = 3, y = 0.2, z = 1, yaw = 90},
	{id = "saw-1", x = 4.5},
	{id = "spikes-1", y = -0.24},
}
```

A pose takes `x`, `y`, `z`, `yaw`, `pitch`, `roll` (degrees), `lookX`,
`lookY`, `lookZ` (a point to face, upright, as `lookAt` does: a camera
that follows the player aims at it every frame), a uniform
`scale` (or `scaleX`, `scaleY`, `scaleZ` for one axis, which squash and
stretch a node), `opacity` and `hidden`. Omitted fields keep their value, and an
unknown id is ignored, so poses can describe entities the template has
already removed. Poses move each node's outer `SCNNode`; its content, `spin`,
`bob` and transitions live on an inner node, so poses and behaviours never
overwrite each other.

## Game loop hooks

- `onFrame(view, dt)` runs from the view's display link while it is in a
  window, with the real interval in seconds. Cap `dt` in the controller so a
  stalled run loop resumes instead of leaping ahead.
- `onKey(view, key, pressed) -> handled` reports presses and releases, never
  repeats. Keys are `left`, `right`, `up`, `down`, `space`, `return`,
  `escape`, `tab`, `delete` or the lowercased character. A key the callback
  declines goes up the responder chain; Command shortcuts go to the menu.
  Held keys are released when the view loses focus or its window stops
  being key, so a key let go elsewhere never stays down. On iPad a hardware
  keyboard reports the same names.
- `onSwipe(view, direction)` sends `left`, `right`, `up` or `down` as soon
  as a drag (a finger on iOS, the mouse on the Mac) has travelled 24 points,
  along the axis it moved most; `onTap(view)` reports a press released
  without travelling. One drag is one swipe or one tap, never both, so a
  game can use a swipe to steer and a tap to stop or continue.

### Game controllers

`view.gamepad` reads the connected game controller each frame:
`{stickX, stickY, a, b, x, y}`, the left stick's tilt (y up; the d-pad
when the stick rests) and which face buttons are down, or nil when none is
connected. It is the GameController framework's `GCController.current`, so
a real controller works on the Mac, iPhone and iPad alike.

`virtualGamepad="true"` puts Apple's on-screen controller
(`GCVirtualController`) over the view on a touch screen while the view is
in a window: a thumbstick on the left and A, B, X and Y on the right. It
reads through `gamepad` like a real one. The Mac has no on-screen
controller. A game played with it should lock its window to landscape
(`<Window orientation="landscape">`).

SceneView is one native class for AppKit and UIKit
(`src/shared/scene_view.m`): templates, poses and hooks are identical, and
only events and colours differ. The iPhone host renders it through the
streaming runtime like any other view.

Test hooks: `bridge._sceneSend(view, "swipe", direction)`, `"tap"`, and
`"drag", x0, y0, x1, y1` (screen points, y down) which runs the gesture
classifier.

## Architecture for a game

A game keeps the project's MVC rules. Each concern has one home:

```
apps/<game>/
  catalog/            authored data: levels, waves, items
  models/             World (entities, clock, events) and one-rule systems
  Model.lua           the session: progress, lives, score, state machine
  controllers/        input, stage (scene template + poses), HUD
  Controller.lua      window, frame loop, coordination
  views/              Window, Stage and HUD templates
  views/prefabs/      one etlua partial per entity kind
  assets/             models and textures, with their license
```

- **Data.** Author levels as data, such as text maps, so designing one never
  touches code. Test that each authored level parses and can be completed.
- **Model.** Keep entities as plain tables. Run behaviour as systems, each
  `update(world, dt, input)` holding one rule, in a fixed order. Systems
  emit events (`coin`, `hurt`, `cleared`) rather than calling the session;
  the session decides what an event means. Nothing in the model requires
  `AppKit` or knows a node, so every rule runs headless on a hand-built map.
- **Input.** Take input through an interface (`nextDirection()`), so tests
  can script it.
- **Revision.** The session increments a `revision` whenever something
  visible changes beyond poses: a pickup, a life, a new state.
- **Controller.** Each frame: step the session, render the stage and HUD
  templates only if `revision` moved, then assign `model:poses()` to
  `nodeStates`. Copy model entities into plain view records before
  rendering, because `partial()` adds its helpers to the table it receives.
- **Prefabs.** An entity kind's look lives in its partial: model, scale,
  idle behaviour and transition. A coin that is taken leaves the scene data
  and pops out through its own `transition`; no code animates it away.

## Testing

Test the model, systems, input and view data directly. Then drive the whole
game through the real view without a window:

```lua
local bridge = require("AppKitNative")
local app = Controller.new({levels = {{id = "mini", title = "Mini", map = {"@$F"}}}})
app:createWindow()
local view = app.stage.view
bridge._sceneSend(view, "key", "right", true)       -- onKey
for _ = 1, 20 do bridge._sceneSend(view, "frame", 1 / 60) end   -- onFrame
local nodes = bridge._sceneNodes(view)
t.expect(nodes["coin-1"] == nil, "a taken coin leaves the scene")
```

`bridge._sceneNodes(view)` returns every identified node keyed by id, with
its `kind`, `parent`, `x`/`y`/`z`, `yaw`, `scale`, `opacity`, `hidden`,
`parts` (content pieces), `spinning`, `bobbing`, `camera` (the point of
view) and `light` (its type). Transitions are SceneKit actions that only
advance while the scene renders, so headless tests see a node's starting
state (an inserted `pop` node at scale 0) and never a finished animation.
Capture visual states with `--capture-plan`; see `AGENTS.md`.

## Offline: the same scenes in a reel

Reel's `<SceneView>` (`modules/reel/reel/world.lua`, see
[its README](../modules/reel/README.md#scenekit)) renders this vocabulary
offline, every attribute a function of time: `spin`, `bob` and
`transition` are computed from `t`, and `states=` plays the role of
`nodeStates`. Models load through the same loader
(`src/shared/scene_models.m`). The promo reel renders Coin Quest's own
`Stage.etlua`, posed by a replay of its own `Model`
(`reels/promo/CoinQuest.lua`).
