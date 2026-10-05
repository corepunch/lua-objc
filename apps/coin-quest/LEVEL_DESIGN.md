# Coin Quest level direction

Coin Quest is a small, explorable 3-D platformer: a welcoming place to run,
jump, discover routes and climb towards visible landmarks. Super Mario 64
is the gameplay reference. The supplied Kenney Platformer Kit scene is the
visual reference: rounded grassy or snowy terraces, warm earth sides,
wooden bridges, clustered plants, trees and small groups of props.

This document records the direction implemented in the level population
pass of 5 October 2026 and guides subsequent level work.

## Ground and recovery

Each of the ten courses now has continuous, solid ground beneath its raised
route. Missing a platform lands the player on grass or snow, with a way
back to the course. The ground is a scaled Kenney terrain piece using the
existing palette texture, with matching collision geometry. It is not a
decorative plane that the player falls through.

Keep generous landing space below bridges, stepping stones, springs and
both ends of moving platforms. A fall should usually cost height and a
short return journey. Ramps, low ledges, springs and lifts provide that
return journey. Checkpoints mark meaningful progress on longer climbs.

The outer coastline is still a boundary: falling into the surrounding ocean
costs a life. Saws and raised spikes remain hazards. Safe ground should not
remove the reason to learn each course's main mechanic or bypass a required
gate.

## Routes and rewards

Begin with room to learn movement. Green Meadow starts with a gentle ramp
and a broad hub, then offers three landmarks: the orchard, the lookout and
the summit. The summit door remains visible before the finish flag appears.

Use coins to suggest routes and lead the player towards useful discoveries.
The current objective remains collecting every coin, then reaching the flag;
each world also has three optional stars. Put optional rewards on detours,
crate climbs or higher lookouts. Give the player a clear way to return from
those detours.

Use wide landings for required early jumps. Introduce a mechanic in a
forgiving setting before combining it with height, timing or hazards.
Preserve different approaches where they are useful: a short jumping route
and a longer ramp can lead to the same place.

These choices draw on the emphasis on enjoyable movement and forgiving
3-D jumps in the [1996 Super Mario 64 developer interviews](https://shmuplations.com/mario64/).
They are design guidance for Coin Quest, not a claim that its current
coin-and-flag progression reproduces Mario 64's mission structure.

## Objects and visual composition

Use the actual [Kenney Platformer Kit](https://kenney.nl/assets/platformer-kit)
models already in `assets/models/`, including their grass and snow variants
and shared `Textures/colormap.png`. Keep the simple palette and rounded
silhouettes consistent with the supplied reference image.

Populate areas with a purpose. Trees frame a clearing; crates and barrels
make a supply stop; flowers mark a welcoming path; signs point towards a
ramp; fences define an edge. Arrange objects into small, readable groups,
with open space between them. Each course should have its own recognizable
places rather than the same scattering of objects everywhere.

Keep movement and sightlines clear. Tree trunks, crates, barrels and fences
have collision, so place them beside approaches and outside landing lanes.
Check the view from the following camera as well as an overview. Tall
terrain or a harmless-looking prop can hide the hero or the next step.
The keep's entrance poles were moved out of the corridor for this reason.

## Lighting and shadows

Use a single directional sun to make height and object placement readable.
Every course now uses a native 2048 × 2048 SceneKit shadow map, with a small
one-texel filtering radius and four samples to soften pixel stair steps
while retaining crisp silhouettes. Trees, crates, bridges, terrace rims,
collectibles and the hero cast real shadows onto the terrain. Ambient fill
keeps shaded surfaces readable without flattening them.

The sun aims at the recovery ground's centre. Its fixed orthographic
coverage includes the ground diagonal plus a six-unit margin for projecting
shadows beyond objects. Camera movement does not move or resize this map.
Keep new terrain and tall props inside that coverage, and check both the
course edge and the tallest landmark when editing a world. Lighting lives
in `views/Stage.etlua`; `StageController` supplies the per-level framing.

This uses the existing map resolution and SceneKit's own rendering on
macOS and iOS. There is no baked shadow artwork, extra light, or shadow
update loop. Verify contact under the hero, shadows across ramps and bridge
planks, and tree silhouettes on both grass and snow.

## What is populated now

All ten worlds have safe ground, authored scenery and broad approach ramps.
Green Meadow received a new route layout; the other courses retain their
main mechanics and receive approaches and scenery around them. Locked Keep
also received an enclosed courtyard to preserve its gate challenge.

The ramp counts below refer to broad terrain approach ramps; existing
narrow slopes and wooden ramps are additional pieces.

| World | Populated areas and objects | Broad ramps and their role |
|---|---|---|
| [Green Meadow](catalog/levels/meadow.lua) | Crate orchard, bridge lookout, terraced summit and door; trees, flowers and mushrooms frame the return paths. | 3: opening hub, orchard and side approach to the hill. |
| [Spring Cliffs](catalog/levels/springs.lua) | Groves around the spring meadow, signs, flowers and a small supply group; bridges connect the cliff tops. | 3: starting area and approaches to spring platforms. |
| [Saw Ridge](catalog/levels/saws.lua) | Timber yard with crates, barrels and fences; tree groups and signs beside the ridge. | 4: start, western route, first ridge platform and eastern branch. |
| [Plank Bay](catalog/levels/bay.lua) | Dock stores, rope fencing, trees and ground cover beside the plank runs. | 4: hub and the western, eastern and northern destinations. |
| [Ferry Lagoon](catalog/levels/lagoon.lua) | Cargo groups distinguish ferry stops; trees, barrels, crates and signs frame the approaches. | 4: hub and three destination approaches. |
| [Locked Keep](catalog/levels/keep.lua) | Supply yard outside, garden inside, enclosing walls and a clear gate corridor. | 4: start, western yard, spring approach and courtyard climb. |
| [Frost Slopes](catalog/levels/frost.lua) | Snow groves, rocks and a supply yard; a crate reward remains on the eastern platform. | 3: start, western route and eastern reward platform. |
| [Glacier Lifts](catalog/levels/glacier.lua) | Lift base camp with supplies, signs, rope fencing and perimeter pines. | 3: start and both lift approach platforms. |
| [Avalanche Loop](catalog/levels/avalanche.lua) | Rock garden inside the loop; supply stops, trees and signs around its outside. | 4: start and eastern, western and northern return routes. |
| [Flagspire](catalog/levels/flagspire.lua) | Snowy trailhead, supply groups and trees around the spire; space under the spiral stays open. | 4: start and the outlying low platforms. |

## Authoring rules

Edit placements in `catalog/levels/*.lua`. Use `blocks` for terrain, `props`
for scenery and solid objects, and the named item lists for gameplay
entities. Keep scene construction in the etlua templates.

1. Place the ground first, with its top at `y = 0`. Extend it beyond the
   course, including moving-platform endpoints and a landing margin.
2. Use `w`, `d` and `h` to size both the model and collision solid. `yaw`
   rotates both together. Use explicit `y` for adjoining terraces and
   ramps so widening a piece does not accidentally stack another on it.
3. Connect the ramp's high end to its destination. Account for the hero's
   radius: a body can hit a ledge before its feet reach the ramp's high end.
   A ramp that looks connected must also be walkable without a jump.
4. Keep solid props out of approaches and exits. Recheck rewards after
   moving a prop: items placed by ground height can fall to the lawn if
   their supporting crate moves away.
5. Preserve a course's challenge when adding ground. Check gate bypasses,
   lift access, spring approaches and return paths from optional rewards.
6. Keep scenery static. This population pass uses ordinary model nodes and
   collision solids, with no new terrain engine, update loop or decorative
   animation system.

## Verification

Run `./lua-objc --test tests/coin_quest.test.lua`. It checks reachability,
safe landings in former gaps, landing margins, ramp traversal with the real
hero, scenery on land, gate behavior, terrain rendering data and stable
shadow coverage in every world. Its graph
checks complement movement tests; they do not replace playing a route or
checking what the camera can see.

Capture every changed world, inspect both overview and playable camera
views, and check small and large windows plus light and dark appearance.
Include missed jumps, collected items, the unlocked keep and completion
states when those areas change. Use the screenshot and capture-plan
commands documented in the repository's agent guide.

The promo reel replays the actual meadow. When its start or route changes,
update `reels/promo/init.lua` and run `tests/promo_reel.test.lua` too.

Further population should improve landmarks, route readability and places
to explore while preserving safe recovery and clear movement lanes. The
current broad ground pieces and scenery pass are the starting point for
that work; they do not mean every later course has received a full route
redesign.
