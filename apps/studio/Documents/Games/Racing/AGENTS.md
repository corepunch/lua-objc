# Racing: rules for changing this game

This is a 3-D racing game built on the shared game layer (`game.Game`,
`game.Session`, `game.World`, `game.Input`, `game.Stage`, `game.Hud`,
`game.cameras.Chase`). Its models come from Kenney's Racing Kit,
`assets/kenney/racing-kit/`. Keep the game working at every step: the
person asking may be a child who cannot fix broken code.

Before you change anything, call `readDocumentation("games")`. Before you
place or add a model, call `readKit("racing-kit")`.

## Where each change goes

| The request | Change | Never |
|---|---|---|
| a new race, or a track changed | `catalog/tracks/<id>.lua`, plus one line in `catalog/Tracks.lua` | code in a track |
| more or fewer laps, easier or harder rivals | the track's `laps`, its `rivals` and their `pace` | a new system for one race |
| trees, stands, tents, banners | the track's `scenery` list | scenery placed from Lua |
| another car for the player | the track's `car`: `raceCarRed`, `raceCarGreen`, `raceCarOrange`, `raceCarWhite` | |
| a different look for a car | `views/prefabs/Car.etlua` | a look set from Lua |
| a new kind of thing (boost pads, oil, pickups) | entities spawned in `models/World.lua`, one rule in `models/systems/<Name>.lua` listed in `SYSTEMS`, a prefab, a loop in `views/pages/Stage.etlua`, and its data in tracks | rules inside the stage, the controller or a view |
| faster cars, sharper steering | `RULES` in `models/World.lua` | per-track physics |
| what an event means (podium, points) | `REACTIONS` in `Model.lua` | the session's state machine |
| the HUD | `views/sections/Hud.etlua`, data from `Model:status()` | |

## Tracks are data

```lua
track = {"start", "long", "long", "wideRight", "long", "wideRight", ...}
rivals = {{"raceCarGreen", pace = 0.8}, ...}
scenery = {{"treeLarge", x, z, yaw = 30, scale = 1}, ...}
```

- The road is a list of pieces driven in order; the game joins each piece
  to the end of the one before. It begins with `"start"` at x 0, z 0,
  driving toward +z. A right turn bends toward −x, a left toward +x.
- Pieces, in road widths: `start` and `long` are 2 long, `straight` 1.
  Corners: `left` / `right` (tight, radius 0.5: cars must slow down),
  `wideLeft` / `wideRight` (radius 1.5), `sweepLeft` / `sweepRight`
  (radius 2.5, taken flat out). A corner moves the road as far forward as
  to the side: a `wideRight` ends 1.5 ahead and 1.5 to the right.
- The list must come back to the start, facing forward, without running
  over itself. Two tight turns the same way make a hairpin: the road comes
  back right beside itself.
- Scenery is placed freely by the middle of the model (x, z, in road
  widths), at any `yaw`, anywhere off the road. Gantries (`overhead*`) may
  span the road; put one over the start at `0, 1`.
- Up to three rivals. `pace` is a share of the player's top speed, 0.5 to
  1. Rivals also slow for corners, so a twisty track is easier to win.
  Keep races winnable: the first races in the 0.7s, the last in the 0.9s.
- `laps` is 1 to 9. Finishing in the top three goes on to the next race.

`models/Level.lua` checks every track when it loads: the track starts with
`start`, every piece name exists, the road joins up and never runs over
itself, every model exists, and no scenery stands on the road. If the
preview reports such an error, read it: it says where the track ends
instead of at the start, or which piece or scenery is wrong. Fix the track
data; never weaken the check.

## Rules of the code

- Inside a list, wrap each `require` in parentheses, as `catalog/Tracks.lua`
  and `SYSTEMS` do: `require` returns a second value that would join the list.
- Systems are `update(world, dt, input)` over plain tables. They emit events
  (`world:emit("lap", car)`); every event needs a reaction in `Model.lua`.
- A car's `yaw` is its heading in degrees: it drives along (sin yaw, cos yaw).
  Steering right lowers it.
- Input is `input:axis()` (x steers, z −1 drives, z 1 brakes) and
  `input:held("gas")` / `input:held("brake")`.
- Things that move every frame move through `World:poses()`, never by
  rendering the stage again. The HUD renders only when an event changes
  what it shows; do not emit an event every frame.
- Views are etlua only. Controllers do not build views. No `ns.*` view
  constructors, no timers, no per-frame template renders.

## After every change

Reload the preview. It must report ready, with no error. Drive a lap: the
countdown runs, the car drives and steers, and the lap counter moves.
