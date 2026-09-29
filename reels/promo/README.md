# lua-objc promo

A 30-second, 1080p film about lua-objc, made with lua-objc. It shows a
family of ordinary native apps first, then the development loop (an agent
editing an app in Lua Studio on the iPad, then by voice on the iPhone), then
the 3-D side (Coin Quest), and ends on the Mac, iPad and iPhone together.

```sh
make promo-reel             # → build/lua-objc-Promo.mov (captures first if missing)
make promo-reel-captures    # recapture after an app changes (Mac windows + Simulators)
./lua-objc reels/promo/init.lua stills /tmp 3.2,9.1,21.55
./lua-objc reels/promo/init.lua render /tmp/part.mov 13 17
REEL_SUBFRAMES=1 ./lua-objc reels/promo/init.lua stills /tmp 5.6   # quick, no motion blur
```

## What is real

Every app on screen is a lua-objc app running natively, captured by the
pipeline, not mocked up:

| Seen as | Source | Captured |
|---|---|---|
| Todo, Notes, Ledger on the Mac | `demo/todo`, `demo/notes`, `demo/ledger` | `lua-objc --capture`: window content and layout dump |
| Weather on the Mac | `apps/weather --showcase` | the same |
| Todo on the iPhone | `demo/todo` on the UIKit host | iPhone Simulator, streamed by the packager |
| Ledger on the iPad | `demo/ledger`, bundled | iPad Simulator |
| Lua Studio on the iPad | `apps/studio` with `LUA_STUDIO_SHOWCASE` | iPad Simulator, bundled with that version of Todo |
| Coin Quest | `apps/coin-quest`: its `Stage.etlua`, prefabs, models and `Model` | rendered live by the reel's `<SceneView>` |

The agent's edits are real diffs (`edits/*.patch`, listed in `Edits.lua`).
The repository holds each app as it ships; version k is that state with
the later edits reverse-applied, so "before" is the app before the agent
touched it and "after" is the code that produced the next picture. Lua
Studio's conversation shows those same diff lines, and so do the reel's
speed-run chips. `tests/promo_reel.test.lua` keeps every patch applying as
the apps change.

Coin Quest is not a recording: `CoinQuest.lua` steps the game's own session
`Model` and `World` with a scripted pad at 240 Hz, and the reel renders the
game's own `Stage.etlua` with those poses, first on the game phone's screen
and then, after the camera flies into the screen, full frame.

The film itself is Lua, etlua and SceneKit: `modules/reel` renders every
frame from `t`, averages sub-frames for motion blur, synthesises the score
from the same timeline and writes H.264 with AAC.

## Files

| File | Contents |
|---|---|
| `views/Reel.etlua` | Styles, the stage, sub-frames per passage and the order of layers |
| `views/World.etlua` | The one SceneKit world: every device and its screen timeline |
| `views/Wall.etlua`, `views/Corridor.etlua` | The app wall with the game phone; the speed run and the hero composition |
| `views/Quest.etlua` | Inside the game after the cut |
| `views/Type.etlua` | Everything written on the film, pinned to devices through `project()` |
| `views/screens/` | Screen contents: the Mac desktop, Lua Studio's timeline |
| `views/devices/` | SceneKit prefabs: iPhone (portrait or landscape), iPad, display, floating window |
| `Choreography.lua` | The camera and every device as functions of t; the exact meeting points |
| `CoinQuest.lua` | The deterministic Coin Quest replay |
| `Stage.lua` | The studio lighting environment, drawn with the pen |
| `shots.lua` | The voice pill (microphone, waveform, transcript) |
| `Score.lua` | The music and the picture-synced sounds |
| `Edits.lua`, `edits/`, `Conversation.lua` | The agent edits and the Lua Studio conversation built from them |
| `capture.lua` | The capture pipeline (`make promo-reel-captures`) |
| `captures/` | Generated, not committed |

## Shots

| Time | Shot | How |
|---|---|---|
| 0–3.5 | Native apps | One window turns over on the beat: Notes, Ledger, Weather, Todo. The iPhone crosses in front. |
| 2.95–6 | One app, three platforms | The window flies into the display's window slot as the camera pulls back; the iPad arrives from behind. Labels and XML fragments follow the devices. |
| 6–13 | Agent iteration | The iPad turns to camera in Lua Studio. Two prompts are typed and sent; each time the diff and the live preview change. "Zero compile cycle." |
| 13–17 | Voice | The preview lifts off the iPad as a physical iPhone, which the camera orbits. "Add a filter." is spoken; the phone changes. |
| 17–21.8 | Apps | A truck past floating apps, each doing one small thing; then a push into the game phone's screen. |
| 21.8–25 | Native 3D | Cut into the game at the instant the screen fills the frame; the camera flies through the level. |
| 25–27.8 | Say it, change it, see it | A flight down a corridor of devices, one edit per beat, through the words. |
| 27.8–30 | Hero | Mac, iPad and iPhone at different depths and angles; the end card. |

## Continuity

Three hand-offs are exact, computed rather than eyeballed, and tested:

- The montage window lands centred on the display's screen at the size the
  desktop draws it, facing the same way; the desktop's window appears as the
  flying one disappears.
- The iPhone starts as Lua Studio's preview: lying on the iPad's glass at
  the preview's centre and height, turned with the iPad, before rising free.
- At the cut into the game the camera looks straight into the game phone's
  screen from the distance at which the screen's height fills the frame, with
  the lens the game camera continues with, so the game on the glass and the
  game full frame are the same picture.
