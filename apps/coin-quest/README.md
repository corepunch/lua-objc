# Coin Quest

A small 3-D puzzle-action game on SceneKit, written as an ordinary lua-objc
app. Hop around floating grass islands, take every coin, dodge saws and
spike traps, then reach the flag that rises once the last coin is gone.

```sh
make run ARGS="apps/coin-quest"
```

Arrow keys or WASD hop one cell. Return or Space continue after a level
ends, R (or the toolbar button) restarts.

On a touch screen, **swipe** to run: the hero keeps hopping that way until
you tap to stop it, swipe another way to turn it, or it reaches an island's
edge. A tap after a level or game ends continues, like Return. Try it in
the iPhone Simulator:

```sh
make ios-run PROJECT=apps/coin-quest
```

The Mac accepts the same gestures with the mouse (drag to swipe, click to
tap), so the touch controls can be tried without a device.

The point of the example is the architecture. A game is usually where
code turns to spaghetti: input handlers that move meshes, meshes that
decide the score, one `update()` that knows everything. Here, each concern
has one home and can be tested without a window. `tests/coin_quest.test.lua`
checks every layer in well under a second, then plays a level through the
real SceneView.

## Layers

```
catalog/Levels.lua          authored level maps: data, nothing else
models/Level.lua            parses a map: tiles, scenery, spawns, walkable()
models/World.lua            one running level: entities, clock, events, poses()
models/systems/*.lua        one rule each: Movement, Patrol, Traps, Pickups, Hazards
models/Animation.lua        the hero's squash, stretch, shake and spin; the flag's sway
Model.lua                   the session: levels, lives, score, state machine
controllers/InputController keys and swipes -> directions and commands
controllers/StageController scene data -> Stage.etlua; poses -> SceneView
controllers/HudController   status -> Hud.etlua
Controller.lua              window, game loop, coordination
views/Window.etlua          toolbar, stage and HUD hosts
views/Stage.etlua           camera, lights and the level's scene graph
views/prefabs/*.etlua       one prefab per entity kind
views/Hud.etlua             level, coins, lives, messages
assets/models/              Kenney Platformer Kit models (CC0, see License.txt)
```

### Data: levels are text

A level is a map where each character is a cell (`@` start, `$` coin, `H`
saw, `^` spikes, `T` tree, …). Designing a level never touches code, and
the test suite checks that every authored level parses and that every coin
and the flag can be reached from the start.

### Model: entities, systems, events

`World` holds plain entity tables (the player, coins, saws, spikes, the
flag) and runs the systems in a fixed order every step. Each system is a
module with a single `update(world, dt, input)` holding one rule:

| System | Rule |
|---|---|
| `Movement` | the player hops cell to cell onto walkable ground |
| `Patrol` | saws run along their row or column and turn at edges |
| `Traps` | spikes rise and sink on a staggered cycle |
| `Pickups` | landing takes coins; the last coin raises the flag; the flag clears the level |
| `Hazards` | saws and raised spikes hurt a player who is not recovering |

Systems never reach up into the session. They emit events (`coin`,
`flagRaised`, `hurt`, `cleared`). `Model` (the session) turns those into
game meaning: score, lives, respawning, the next level, game over. Adding a
rule means adding a system file and a test, not threading a flag through
an update loop.

The Kenney models are static OBJ files, so the hero's life is procedural:
`Animation` turns the world's clock and a few timestamps the systems leave
on the player (`landedAt`, `hurtAt`, `clearedAt`) into squash and stretch,
a shake when hurt, a victory spin and the flag's sway. They are pure
functions of time, posed each frame through `scaleX/Y/Z` and `yaw`.

Nothing in `models/` or `Model.lua` knows about SceneKit, AppKit or etlua,
so all of it runs headless with a hand-built three-cell map.

### View: the scene graph is a template

`Stage.etlua` describes the scene the way any lua-objc screen describes
its views:

```xml
<SceneView id="scene" background="#a9dcf5" onKey="key" onFrame="frame">
	<Camera id="camera" position="<%= camera.position %>" lookAt="<%= camera.lookAt %>" />
	<Light id="sun" type="directional" rotation="-58 38 0" castsShadow="true" />
	<Node id="level-<%= level %>">
		<% for _, coin in ipairs(coins) do -%>
		<%- partial("prefabs/Coin.etlua", {id = coin.id, x = coin.x, z = coin.z, assets = assets}) %>
		<% end -%>
		…
	</Node>
</SceneView>
```

Prefabs are partials. `prefabs/Coin.etlua` is the whole definition of what
a coin looks like and how it behaves visually:

```xml
<Node id="<%= id %>" model="<%= assets %>coin-gold.obj" position="<%= x %> 0.15 <%= z %>"
      spin="150" bob="0.08" transition="pop" />
```

The spin and bob run natively as SceneKit actions. When the coin is taken,
the model drops it from the scene data, the template renders without it,
and the SceneView reconciler plays its `pop` as it leaves. No code says
"animate this coin away". The same goes for the flag, which `rise`s in when
it appears in the data.

### Controller: structure on change, motion every frame

The SceneView's display link calls `Controller:tick(dt)` every frame:

1. `model:step(dt, input)` advances the game.
2. If `model.revision` moved (a coin was taken, a life was lost, the state
   changed), the stage and HUD templates render again. Retained
   reconciliation keeps every unchanged node and label as it was.
3. `stage.nodeStates = model:poses()` moves the player, saws and spikes.

Structure goes through templates, which only run when something changes.
Motion is a flat list of poses assigned every frame. Neither path knows
about the other's details, and the controller knows no game rule.

`StageController` copies model entities into plain view records before
rendering, so templates never hold live game state, and it frames the
camera on the level. `InputController` remembers taps shorter than a frame
and lets the latest held direction win, so controls feel like a game pad.

## Assets

The models come from Kenney's
[Platformer Kit](https://kenney.nl/assets/platformer-kit) (CC0, see
`assets/License.txt`). SceneKit imports the OBJ files with their MTL
materials and the shared `Textures/colormap.png` palette; `SceneView`
clones each model per node.
