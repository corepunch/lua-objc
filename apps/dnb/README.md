# Drum & Bass — an endless electronic music generator

Endless DJ sets in seven electronic styles, every sound synthesized in Lua:
no samples, no audio files. Even the Amen break is recreated, kit and room,
then played the way jungle producers played it: a sped-up loop cut into 16th
slices and rearranged. Press Play and one seed plays a set that never
repeats. Tracks follow each other in the style's flavours, in keys a DJ could
mix between, each new intro mixed under the outgoing tune.

| Style | Flavours | Tempo |
|---|---|---|
| Drum & Bass | Liquid, Jungle, Neurofunk, Rollers | 160–180 |
| Techno | Peak Time, Acid (303 line), Hypnotic (dub stabs) | 124–140 |
| House | Deep, Classic, Disco (octave bass) | 118–128 |
| Trance | Uplifting, Progressive, Psytrance (galloping bass) | 132–145 |
| Dubstep | Deep, Brostep, Riddim (per-note wobble rates) | 136–150 |
| Breakbeat | Big Beat, Nu Skool, Florida Breaks | 120–140 |
| UK Garage | 2-Step, Speed Garage, Future Garage | 128–138 |

The visualizer fills the window, running under the Liquid Glass toolbar;
the now-playing cards, the lit pads (after the Logic Pro Drum Machine
Designer) and the fill bars float over it in glass. The Style menu switches
genre on the next bar line; pads a style does not play are disabled and some
are relabelled (Clap, Acid, Wobble). The Scene menu pins one visualizer scene
or leaves the director to pick one per section and phrase. Next Track mixes
into the next track of the set, New Set starts a new seed, and Mini Player
(`pip.enter`) shrinks the app into a floating 16:9 window, after the Music
app's MiniPlayer and Picture in Picture, that keeps playing the visualization
with a glass transport bar. Closing it brings the main window back.

```sh
make run ARGS=apps/dnb
```

## Plugins

Styles and visualizer scenes are plugins, built on the framework's
[`Plugins`](../../lua/Plugins.lua) module (see
[ARCHITECTURE.md](../../ARCHITECTURE.md#plugins-luapluginslua)). Each is a
folder whose `init.lua` returns a manifest. It runs isolated: pure standard
libraries only, with everything else coming from a read-only host API.

**Style plugins** (`plugins/styles/<id>/`) declare a title, symbol, tempo
range, control defaults, the parts they play, pad labels and a `sound` that
tunes the Synth. `create(kit, seed)` returns a composer whose `bar(n,
settings)` is a pure function of seed, bar and settings. The kit
([`host/StyleKit.lua`](host/StyleKit.lua)) is the shared functionality:
seeded randomness, modes, voice-led chords, a call-and-response melody
writer, the DJ set that sequences tracks and sections, the bar score with
humanized hits, arrangement punctuation (crashes, risers, build rolls), the
blend into a new track, and the Amen break. Adding a genre is one folder and
one line in [`host/Styles.lua`](host/Styles.lua).

**Visualizer plugins** (`plugins/visualizers/<id>/`) are declarative: a
title, symbol, the sections the director shows them in, and a `Scene.metal`
defining `<id>Scene(inputs, uv, frame)`. The host analyses the audio once
([`models/Visuals.lua`](models/Visuals.lua)) and
[`views/Visualizer.etlua`](views/Visualizer.etlua) links the shared Metal
library ([`shaders/Kit.metal`](shaders/Kit.metal)), every scene, a
dispatcher and the entry point
([`shaders/Main.metal`](shaders/Main.metal)) into one `<ShaderView>` program,
so any two scenes can crossfade.

Scenes compose around the **stage**, the main view rect: the part of the
picture between the toolbar and the top of the panels (or the mini player's
transport bar). The controller measures it from each window's layout and
packs it into the shader header; `stagePoint(uv, frame)` gives a point in
stage heights centred on it, so the horizon runs through the middle of the
stage rather than the window, and the picture continues behind the panels.

| File | Role |
|---|---|
| `Model.lua` | Parts and controls (the single source for the pads and fill bars), the current style's ranges, labels and supported parts |
| `Controller.lua` | Window, transport, Style and Scene menus, the mini player, and the 60 Hz display loop |
| `host/Styles.lua`, `host/StyleKit.lua` | The style extension point and its host API |
| `host/Visualizers.lua` | The visualizer extension point and the program it links |
| `plugins/styles/*` | Drum & Bass, Techno, House, Trance, Dubstep, Breakbeat, UK Garage |
| `plugins/visualizers/*` | Synthwave Horizon, Ridge Flight, Liquid Chrome, Light Trails, Tunnel, Crystals |
| `models/Synth.lua` | Sample-accurate synthesis: designed kicks, snares, claps and hats per style, shared cymbals and percussion, the Amen loop and its slice sampler, reese/acid/wobble bass with resonance, filter envelope, accents and retriggered LFO, sub, pads, FM electric piano, stabs, arp plucks, a gliding lead, risers, ping-pong delay with throws, reverb, sidechain pump, soft clip |
| `models/Amen.lua` | The recreated Amen break's four-bar pattern and slice bookkeeping |
| `models/Visuals.lua` | Spectrum smoothing, peak holds, kick and snare flashes, the scene director with crossfades, and the shader value layout |
| `services/AudioOutput.lua` | Speaker output through [AudioStream](../../src/plugins/audio/README.md) |
| `views/` | Window, now-playing cards, pads, controls, the linked visualizer and the mini player |

While playing, the controller tops up a 0.3 s audio queue (the latency for
control changes), maps the device's played frame to the sounding bar for the
header, and feeds the analysed spectrum to every open visualizer. Full
synthesis costs about a fifth of one core at its busiest.

Tests: `tests/dnb.test.lua` (the drum & bass set, composition, synthesis,
visuals, the controller with a fake output, the native plugin),
`tests/dnb_plugins.test.lua` (the contract every style plugin keeps, style
switching, scene pinning, the mini player), `tests/plugins.test.lua` (the
framework), `tests/shader_view.test.lua`, `tests/window_chrome.test.lua`,
`tests/control_styles.test.lua` and `tests/fixed_size.test.lua`.
