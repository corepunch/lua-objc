# Coin Quest

A small 3-D platformer on SceneKit, written as an ordinary lua-objc app, in
the spirit of Mario 64 and Kenney's own
[3D platformer starter kit](https://github.com/KenneyNL/Starter-Kit-3D-Platformer).
Ten little worlds of floating islands built from Kenney's
[Platformer Kit](https://kenney.nl/assets/platformer-kit): run and jump
across them, take every coin, then reach the flag that rises once the last
coin is gone. Three stars hide in each world.

```sh
make run ARGS="apps/coin-quest"
```

| | Keys | Game controller, or the on-screen one |
|---|---|---|
| Run | arrows or WASD (two at once run diagonally) | left stick or d-pad |
| Jump | Space | A or B |
| Turn the camera | Q and E | X and Y |
| Continue after a level | Return or Space | A or B |
| Restart the game | R, or the toolbar button | |

Directions are as seen from the camera: up runs away from it. The camera
follows on a leash, as Mario 64's does: running away pulls it along, running
sideways swings it round, running at it backs it off.

On a touch screen the game is landscape only and shows Apple's on-screen
game controller (`GCVirtualController`): a thumbstick on the left, A, B, X
and Y on the right. A swipe on the scene also runs and a tap jumps, so the
Mac's mouse can try the touch controls. Try it in the iPhone Simulator:

```sh
make ios-run PROJECT=apps/coin-quest
```

## The worlds

| | World | What it teaches |
|---|---|---|
| 1 | Green Meadow | running, jumping, a plank bridge, stepping stones, an arch |
| 2 | Spring Cliffs | springs throw you onto the cliffs; bridges join their tops |
| 3 | Saw Ridge | saws sweep a ridge climbing north |
| 4 | Plank Bay | loose planks fall a moment after you land; spikes |
| 5 | Ferry Lagoon | ferries and a lift |
| 6 | Locked Keep | a gate in a walled corridor; the key is up a spring |
| 7 | Frost Slopes | snow; slopes and wooden ramps; small hexagon stones |
| 8 | Glacier Lifts | lifts up the glacier, saws on top |
| 9 | Avalanche Loop | everything, round a frozen lake, with checkpoints |
| 10 | Flagspire | a spiral of stones up the spire |

## Layers

```
catalog/levels/*.lua        one world each: blocks, props and items placed in 3-D
catalog/Levels.lua          the worlds in play order
catalog/Blocks.lua          the kit's ground pieces: size and the shape of their top
catalog/Props.lua           the kit's other pieces: model, scale, collision box
models/Level.lua            builds a world: stacks the blocks, places props and items
models/Terrain.lua          collision: turned boxes with flat, ramp and arch tops
models/Reach.lua            checks a world can be cleared with the hero's jump
models/World.lua            one running world: entities, clock, events, poses()
models/systems/*.lua        one rule each: Platforms, Hero, Patrol, Traps, Locks, Pickups, Hazards, Camera
models/Animation.lua        the hero's squash, stretch, shake and spin; springs; the flag
Model.lua                   the session: worlds, lives, score, stars, state machine
controllers/InputController keys, swipes and game controllers -> a run direction, jumps, camera turns
controllers/StageController scene data -> Stage.etlua; poses and the camera -> SceneView
controllers/HudController   status -> Hud.etlua
Controller.lua              window, game loop, coordination
views/Window.etlua          toolbar, stage and HUD hosts; landscape on a touch screen
views/Stage.etlua           camera, lights and the world's scene graph
views/prefabs/*.etlua       one prefab per entity kind
views/Hud.etlua             world, coins, stars, lives, messages
assets/models/              Kenney Platformer Kit models (CC0, see License.txt)
```

### Data: a world is a scene of the kit's pieces

A world is written the way the kit's own sample scene is built: blocks
placed where they stand, turned to any angle, overlapping, stacked.

```lua
blocks = {
	{"large", 0, 4, yaw = 15, h = 0.75},       -- a grass block, turned, squashed to 0.75 high
	{"tall", 8.2, 2.4, yaw = -18, h = 2},      -- a tall one, stretched to 2
	{"arch", -0.6, -0.4, yaw = 82, h = 1.2},   -- an arch over the water
},
props = {
	{"platform", 3.7, 3.9, yaw = -6, y = 0.6}, -- a plank of a bridge over the water
	{"rail", 3, 4.3, yaw = -10, y = 0.75},     -- its rail
	{"crate", -9.8, 3.2, yaw = 30, y = 1.8},   -- a crate stacked on another
},
coins = {{0.2, 4}, {3.7, 3.9, lift = 0.3}},
springs = {{3.8, 3.6}},
movers = {{from = {2.4, 1, 0}, to = {6.5, 1, 0}}},
```

A piece without `y` stands on whatever is under it. A block whose top
another stands on shows the kit's plain model; a top block shows the
overhang model, its grass or snow draping over the edge. Every prop that
can be bumped or stood on has a collision box in `catalog/Props.lua`, so a
bridge is wooden planks you walk on and a fence is a rail you cannot.

Designing a world never touches code. `models/Reach.lua` checks each one:
a graph of the surfaces the hero can stand on, joined where a jump carries
from one to the next. Every coin, star, heart, key and checkpoint must be
within a jump of a surface the hero reaches, the flag must be reachable,
and no surface may be a dead end with no way back. The tests measure the
real hero's jump against the checker's, so a world it passes is never
tighter than it says.

### Model: entities, systems, events

`World` holds plain entity tables and runs the systems in a fixed order
every step. Each system is a module with a single `update(world, dt, input)`
holding one rule:

| System | Rule |
|---|---|
| `Platforms` | ferries and lifts run between their ends and carry a rider; loose planks fall and float back |
| `Hero` | running, jumping, gravity, walls; ramps and steps are walked; springs throw |
| `Patrol` | saws run back and forth |
| `Traps` | spikes rise and sink on a staggered cycle |
| `Locks` | the key opens the gates |
| `Pickups` | coins, stars, hearts, keys, checkpoints; the last coin raises the flag |
| `Hazards` | saws, raised spikes and the water hurt |
| `Camera` | the leash camera follows the hero and turns when asked |

Systems never reach up into the session. They emit events (`coin`,
`flagRaised`, `hurt`, `cleared`). `Model` (the session) turns those into
game meaning: score, lives, respawning at the last checkpoint, the next
world, out of lives. Nothing in `models/` or `Model.lua` knows about
SceneKit, AppKit or etlua, so all of it runs headless.

The Kenney models are static OBJ files, so the hero's life is procedural:
`Animation` turns the clock, the hero's speed and a few timestamps into
squash and stretch, a shake when hurt and a victory spin.

### View: the scene graph is a template

`Stage.etlua` describes the world the way any lua-objc screen describes its
views, and the prefabs are partials:

```xml
<Node id="<%= coin.id %>" model="<%= assets %>coin-gold.obj" position="…" spin="150" bob="0.08" transition="pop" />
```

The spin and bob run natively as SceneKit actions. When a coin is taken the
model drops it from the scene data and the SceneView reconciler plays its
`pop` as it leaves. No code animates it away.

### Controller: structure on change, motion every frame

The SceneView's display link calls `Controller:tick(dt)` every frame:

1. The input reads the SceneView's `gamepad` (a real controller or the
   on-screen one), and `model:step(dt, input)` advances the game.
2. If `model.revision` moved (a coin was taken, a life was lost, the state
   changed), the stage and HUD templates render again.
3. `stage:pose(...)` moves the hero, saws, spikes, ferries and planks, and
   aims the camera at the hero.

## Assets

The models come from Kenney's
[Platformer Kit](https://kenney.nl/assets/platformer-kit) (CC0, see
`assets/License.txt`). SceneKit imports the OBJ files with their MTL
materials and the shared `Textures/colormap.png` palette; `SceneView`
clones each model per node.
