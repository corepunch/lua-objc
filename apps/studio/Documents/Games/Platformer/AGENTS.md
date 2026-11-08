# Platformer: rules for changing this game

This is a 3-D platformer built on the shared game layer (`game.Game`,
`game.Session`, `game.World`, `game.Input`, `game.Stage`, `game.Hud`,
`game.cameras.Leash`). Its models come from Kenney's Platformer Kit,
`assets/kenney/platformer-kit/`. Keep the game working at every step: the
person asking may be a child who cannot fix broken code.

Before you change anything, call `readDocumentation("games")`. Before you
place or add a model, call `readKit("platformer-kit")`.

## Where each change goes

| The request | Change | Never |
|---|---|---|
| a new level, or a level changed | `catalog/levels/<id>.lua`, plus one line in `catalog/Levels.lua` | code in a level |
| more coins, springs, spikes | the level's `coins` / `springs` / `spikes` lists | a new system for one level |
| a different look for a thing | its prefab, `views/prefabs/<Kind>.etlua` | a look set from Lua |
| another hero character | `views/prefabs/Player.etlua`: `character-oodi`, `character-ooli`, `character-oopi`, `character-oozi` | |
| a new kind of thing (a key, a moving platform, an enemy) | entities spawned in `models/World.lua`, one rule in `models/systems/<Name>.lua` listed in `SYSTEMS`, a prefab, a loop in `views/pages/Stage.etlua`, and its data in levels | rules inside the stage, the controller or a view |
| jump higher, run faster | `RULES` in `models/World.lua` | per-level physics |
| what an event means (score, lives) | `REACTIONS` in `Model.lua` | the session's state machine |
| the HUD | `views/sections/Hud.etlua`, data from `Model:status()` | |

## Levels are data

```lua
pieces = {{"block-grass-large", x, y, z, yaw = 25, scale = 1}, ...}
coins = {{x, y, z}, ...}
```

- `y` is where a thing **stands**: a block on the ground has `y = 0`; a coin
  on a block 1 tall has `y = 1`.
- Place pieces freely: any `x`, `z`, any `yaw`, overlapping is fine. There
  is no grid. Turn neighbouring pieces a little so the land looks natural.
- Use the sizes in the manifest so pieces touch. `block-grass-large` is
  2.08 wide and 1 tall; `-tall` is 2 tall; `-low` is 0.5 tall.
- Trees, flowers, rocks and signs are scenery (walked through). Blocks,
  platforms, ramps, crates and fences are solid.
- A ramp (`*-slope`) rises toward its −z side; turn it with `yaw`.
- A normal jump climbs about 1.5 units and crosses about 2.9 units of gap
  at the same height. A spring throws about 3.8 units up.
- Snow levels use `biome = "snow"` and `block-snow-*` pieces.

`models/Level.lua` checks every level when it loads: every model exists,
the start stands on a solid piece, and every coin and the flag can be
reached by running and jumping. If the preview reports such an error, fix
the level data (move the coin, add a stepping stone, add a spring); never
weaken the check.

## Rules of the code

- Inside a list, wrap each `require` in parentheses, as `catalog/Levels.lua`
  and `SYSTEMS` do: `require` returns a second value that would join the list.
- Systems are `update(world, dt, input)` over plain tables. They emit events
  (`world:emit("coin", coin)`); every event needs a reaction in `Model.lua`.
- Input is `input:axis()` (x, z; up is away from the camera),
  `input:take("jump")` once per press, `input:held(name)` while held.
- Things that move every frame move through `World:poses()`, never by
  rendering the stage again. Things that appear or disappear (a coin taken,
  the flag raised) change the scene data and play their `transition`.
- Characters have animation clips (`animation="walk"`); the manifest lists
  them. Do not animate with timers.
- Views are etlua only. Controllers do not build views. No `ns.*` view
  constructors, no timers, no per-frame template renders.

## After every change

Reload the preview. It must report ready, with no error. If it reports a
level error, read it: it names the level, the coin and why.
