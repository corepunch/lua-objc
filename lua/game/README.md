# lua/game

The genre-neutral half of a SceneKit game. A game is an ordinary lua-objc
app (`apps/<game>/`, or a Lua Studio project) that extends these pieces;
`apps/coin-quest` is the reference; Lua Studio's genre templates
(`apps/studio/Documents/Games/Platformer`, `.../Racing`) are smaller ones. See [docs/scenekit.md](../../docs/scenekit.md)
for the scene tags and the architecture they follow.

| Module | What it is | A game supplies |
|---|---|---|
| `game.Game` | root controller: window, input, loop, render on `revision`, poses each frame | `WINDOW`, `Model`, `Levels`, `Stage`, `Hud`, optional `BINDINGS` |
| `game.Session` | levels, lives, score, playing / cleared / over / won | `World`, `parse`, `RULES`, `REACTIONS`, `QUIET`, `status()`, `scene()`, `camera()` |
| `game.World` | entities, clock, events, systems run in order | `RULES`, `SYSTEMS`, `new(level)`, `respawn()`, `poses()` |
| `game.Input` | keys, swipes, taps, game controllers -> `axis()`, `take(button)`, `held(button)`, `turn()` | bindings that differ from `Input.BINDINGS` |
| `game.Stage` | renders the Stage template, poses nodes and camera | `VIEW`, `viewData(scene)` |
| `game.Hud` | renders the HUD template from the session's status | `VIEW`, `viewData(status, hud)` |
| `game.cameras.Leash` | third-person follow camera, a system | `follow`, `cameraNear`, `cameraFar`, `cameraHeight`, `cameraTurn` rules |
| `game.cameras.Chase` | camera behind a car or plane's heading, a system | `chaseDistance`, `chaseHeight`, `chaseAhead`, `chaseFollow` rules; `player.yaw` |

Rules that keep a game readable as it grows:

- **Levels are data.** A level is a table in `catalog/`; designing one never
  touches code. A test parses every level and proves it can be finished.
- **One rule per system.** A system is `update(world, dt, input)` over plain
  entity tables. It emits events; it never calls the session or a view.
- **The look of a thing is its prefab.** `views/prefabs/<Kind>.etlua` holds
  the model, scale, idle behaviour (`spin`, `bob`, `animation`) and
  `transition`. No code animates a node away.
- **Models come from shared kits.** `assets/kenney/<kit>/models/*.glb`; see
  each kit's `manifest.lua` for sizes before placing a piece.
- **Nothing ticks when idle.** The SceneView drives `tick` only while the
  scene is on screen.
