# lua-objc promo

A 30-second, 1080p film about lua-objc, made with lua-objc. Its subject is
the main selling point: building apps right on the iPad and the iPhone. The
agent edits an app from Lua Studio on the iPad while the iPhone beside it
shows each change live and is tapped; then the iPhone alone is talked to
and used; then it turns into a game and the camera goes through its screen;
the Mac appears only in the closing composition.

Screenshots are never shown whole and still. They are cut into their
components (rows, cards, the filter, chat bubbles, diff lines) and the
components move: a change on the phone is a matched-geometry morph in which
every task row keeps its identity and slides to its new place, new
components pop in on springs, removed ones fall away, all on the beat.

```sh
make promo-reel             # → build/lua-objc-Promo.mov (captures first if missing)
make promo-reel-captures    # recapture after an app changes (Mac windows + Simulators)
./lua-objc reels/promo/init.lua stills /tmp 3.2,9.1,21.55
./lua-objc reels/promo/init.lua render /tmp/part.mov 13 17
REEL_SUBFRAMES=1 ./lua-objc reels/promo/init.lua stills /tmp 5.6   # quick, no motion blur
```

## What is real

Every screen is a lua-objc app running natively, captured by the pipeline,
then cut into components:

| Seen as | Source | Captured |
|---|---|---|
| Todo on the iPhone, in seven states | `demo/todo` on the UIKit host | iPhone Simulator, streamed by the packager |
| Lua Studio on the iPad | `apps/studio` with `LUA_STUDIO_SHOWCASE` | iPad Simulator, bundled with that version of Todo |
| Coin Quest | `apps/coin-quest`: its `Stage.etlua`, prefabs, models and `Model` | rendered live by the reel's `<SceneView>` |
| Ledger on the Mac (closing shot only) | `demo/ledger` | `lua-objc --capture` |

The agent's edits are real diffs (`edits/*.patch`, listed in `Edits.lua`).
The repository holds each app as it ships; version k is that state with the
later edits reverse-applied. The states reached by using the app (a task
checked, the Open filter) are the same app with its sample data changed
(`Edits.lua` `states`), kept consistent: the task checked on the iPad's
preview stays checked through the filter. Lua Studio's conversation shows
the same diff lines. `tests/promo_reel.test.lua` keeps every patch and
change applying as the apps change.

The components are found in the screenshots' pixels when the reel loads
(`Regions.lua`): dividers, cards, the filter, bubbles and diff lines. Which
task each row is comes from the app's own model (`Todo.lua`), so a morph
knows which row goes where.

Faked for the film, because it is the product's direction rather than a
shipping screen: the chat drawer on the iPhone (drawn in `Motion.lua`), and
the iPhone beside the iPad standing for Lua Studio's preview.

Coin Quest is not a recording: `CoinQuest.lua` steps the game's own session
`Model` and `World` with a scripted pad at 240 Hz, and the reel renders the
game's own `Stage.etlua` with those poses, first on the phone's screen and
then, after the camera flies into the screen, full frame.

## Files

| File | Contents |
|---|---|
| `views/Reel.etlua` | Styles, the stage, sub-frames per passage and the order of layers |
| `views/World.etlua` | The one SceneKit world: the iPhone, the iPad, the game phone, the closing composition |
| `views/Quest.etlua` | Inside the game after the cut |
| `views/Type.etlua` | Everything written on the film, on the beat; captions and labels |
| `views/screens/Desktop.etlua` | The Mac's desktop in the closing shot |
| `Motion.lua` | Component motion: the phone's morphs, assembly, taps and chat drawer; Lua Studio's chat |
| `Regions.lua` | Components found in simulator screenshots |
| `Todo.lua` | The Todo states and their row order, from the app's model |
| `views/devices/` | SceneKit prefabs: iPhone (portrait or landscape), iPad, display, floating window |
| `Choreography.lua` | The camera and every device as functions of t; the exact meeting points |
| `CoinQuest.lua` | The deterministic Coin Quest replay |
| `Stage.lua` | The studio lighting environment, drawn with the pen |
| `shots.lua` | The screens and captions as reel `<Draw>` shots |
| `Score.lua` | The music and the picture-synced sounds |
| `Edits.lua`, `edits/`, `Conversation.lua` | The agent edits and the Lua Studio conversation built from them |
| `capture.lua` | The capture pipeline (`make promo-reel-captures`) |
| `captures/` | Generated, not committed |

## Shots

| Time | Act | What happens |
|---|---|---|
| 0–3.6 | Open | The Todo app assembles on the iPhone from its pieces, landing on the beats. |
| 3.6–11.75 | iPad and iPhone | A prompt is typed in Lua Studio and sent; the bubble flies up, the answer and its diff arrive. In one held two-shot the phone reflows, a second prompt is sent and lands too. A finger taps a task on the phone and it checks off. "No build. No restart." |
| 13–17.6 | The iPhone alone | Its chat drawer rises, "Add a filter." is spoken, the filter pops in; a tap on Open collapses the finished tasks. |
| 17.6–23.6 | Native 3D | The phone turns on its side into Coin Quest; the camera pushes into the screen and cuts into the game's world. |
| 23.6–30 | Close | The Mac, the iPad and the iPhone take their places; the end card. |

## Continuity

Two hand-offs are exact, computed rather than eyeballed, and tested:

- The phone turned on its side is the game phone: the same place and
  attitude, so the swap from Todo to the game cannot be seen.
- At the cut into the game the camera looks straight into the game phone's
  screen from the distance at which the screen's height fills the frame, with
  the lens the game camera continues with, so the game on the glass and the
  game full frame are the same picture.

The camera holds still while a screen changes (the two-shot holds through
both edits); every event is on the 120 BPM beat grid; the score is
synthesised from the same timeline, with a pop on every change, a tick on
every tap and typed character, chimes on sends and the coins the replay
takes.
