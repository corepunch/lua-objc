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
the now-playing cards, the arrangement strip and the Groove, Sound and Mix
sliders float over it in glass. Each track is arranged before it plays, like
the arrange window of Cubase or MTV Music Generator: sections, and one lane
of blocks per part. The strip draws them as an arrange window
does, one track per instrument (Snare holds the ghosts, Hats the ride, Bass
the sub and the reese) with softly shaded clips that show the fade or filter
sweep riding them. It scrolls right to left past a fixed playhead, lights
the clips that sound and shows the next section change coming. The style decides which parts its songs play; the listener shapes
them with the sliders, and the Mix faders (Drums, Bass, Chords, Melody)
scale the style's own balance. The Style menu switches genre on the next bar
line. The Scene menu pins one visualizer scene
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
range, control defaults and a `sound` that tunes the Synth, and compose in
three parts. `material(kit, rng, track, first)` draws one cycle's grooves,
harmony and melody. `arrange(kit, track, cycles)` lays a track out as lanes
of blocks (the "when"). `patterns` render one bar of a part (the "what").
The host's [`Composer`](host/Composer.lua) builds each track's
[`Arrangement`](host/Arrangement.lua) once, from the seed alone, and renders
bar n from the blocks under it. Energy and Complexity shape the patterns bar
by bar. Blocks are plain data, never overlap in a lane, and point at
patterns by id; structure moves (fills, risers, half-time, throws, chops)
are lanes too, so tests read the plan instead of rendering audio. A block
may carry automation, as a clip does: `level` fades it and `filter` sweeps
a low-pass or a high-pass over it. The composer marks every note with its
block's automation where the note starts, and the Synth plays each voice
through it. A style arranges section by section and ends with
`kit.produce(lanes, track)`, the producer's moves drawn from the track's
seed: parts join a phrase or two late and leave early, the bar before a
phrase lands pulls the kick and bass or the drums out, the drums open
through the intro, the tops thin through a build while the reese is teased
under it, and the outro sheds parts for the next track to mix over. The
`filter` lane sweeps the whole mix, the way an effect machine has patterns
of its own in Jeskola Buzz's sequence.

No two tracks take the same road. Each draws its form from the seed: how it
reaches the first drop (a build, straight out of the intro, or by way of a
melodic passage), what joins one drop to the next (a breakdown and a build,
a build alone, a breakdown the drop slams out of, or nothing: a double
drop), and how long each section runs, in whole eight-bar phrases so that
tracks still line up in the mix. A build winds up in one of four ways: a
snare roll, a kick roll, the drop's groove opening through a filter, or the
drums gone under the riser. A style weights these in its set's `form`
(Trance always breaks down and builds; Techno prefers cold opens and kick
rolls), and the same seed gives each style different forms. The kit
([`host/StyleKit.lua`](host/StyleKit.lua)) is the shared functionality:
seeded randomness, modes, voice-led chords, a drum kit for every track
(a snare character from the flavour's `snares` — tight, fat, rimshot,
roomy, crunchy, layered with a clap, vintage — and a retuned kick, hats and
clap), a call-and-response melody writer, the DJ set that sequences tracks and sections, the bar score with
humanized hits, the lane builder (`add`, `cut`, `automate`), the shared punctuation (crashes, risers,
build rolls, throws), the blend into a new track, and the Amen break. Adding a genre is one folder and
one line in [`host/Styles.lua`](host/Styles.lua).

**Visualizer plugins** (`plugins/visualizers/<id>/`) are declarative: a
title, symbol, the sections the director shows them in, and a
`Scene.metal`. A scene either lists `draws`, meshes whose vertex and
fragment functions (named after its id) compute geometry per vertex from
`vertex_id` and `instance_id` (Light Trails' ribbons, the Solar System's
sun, planets, rings, comets and asteroid belt, Valley Flight's terrain,
water and cloud banks), or defines only `<id>Scene(inputs, uv, frame)` and
is drawn full-screen. The host analyses the audio once
([`models/Visuals.lua`](models/Visuals.lua)) and
[`views/Visualizer.etlua`](views/Visualizer.etlua) links the shared Metal
library ([`shaders/Kit.metal`](shaders/Kit.metal)), every scene and the
finishing pass ([`shaders/Main.metal`](shaders/Main.metal)) into one
`<ShaderView layers="2">` program. The current scene renders into layer 1
and, during a crossfade, the next into layer 2; the finish mixes them and
adds bloom from the layers' mip levels. Geometry belongs in vertices: a
per-pixel loop over a curve's segments made Light Trails take 85 ms a frame.

Scenes compose around the **stage**, the main view rect: the part of the
picture between the toolbar and the top of the panels (or the mini player's
transport bar). The controller measures it from each window's layout and
packs it into the shader header; `stagePoint(uv, frame)` gives a point in
stage heights centred on it, so the horizon runs through the middle of the
stage rather than the window, and the picture continues behind the panels.

| File | Role |
|---|---|
| `Model.lua` | Lanes by family, the timeline's tracks and the parts each gathers, controls (the single source for the sliders), the current style's ranges and which lanes sound |
| `Controller.lua` | Window, transport, Style and Scene menus, the mini player, and the 60 Hz display loop |
| `host/Styles.lua`, `host/StyleKit.lua` | The style extension point and its host API, with the lane builder and the shared patterns |
| `host/Arrangement.lua`, `host/Composer.lua` | A track's plan of sections and lanes, checked and searchable; the composer every style shares, which arranges tracks and renders bars from their blocks |
| `host/Visualizers.lua` | The visualizer extension point, the program it links and the draws that show a scene on a layer |
| `plugins/styles/*` | Drum & Bass, Techno, House, Trance, Dubstep, Breakbeat, UK Garage |
| `plugins/visualizers/*` | Synthwave Horizon, Valley Flight, Solar System, Liquid Chrome, Light Trails, Tunnel, Crystals |
| `models/Timeline.lua`, `views/Timeline.etlua`, `shaders/Timeline.metal` | The arrangement strip: tracks, instanced clips and the headline; track names; clips scrolling past the playhead |
| `models/Synth.lua` | Sample-accurate synthesis: kicks, snares, claps and hats designed per style and voiced anew for every track, shared cymbals and percussion, the Amen loop and its slice sampler, reese/acid/wobble bass with resonance, filter envelope, accents and retriggered LFO, sub, pads, FM electric piano, stabs, arp plucks, a gliding lead, risers, per-voice fades and filter sweeps from the arrangement, ping-pong delay with throws, reverb, sidechain pump, soft clip |
| `models/Amen.lua` | The recreated Amen break's four-bar pattern and slice bookkeeping |
| `models/Visuals.lua` | Spectrum smoothing, peak holds, kick and snare flashes, the scene director with crossfades, and the shader value layout |
| `services/AudioOutput.lua` | Speaker output through [AudioStream](../../src/plugins/audio/README.md) |
| `views/` | Window, now-playing cards, sliders, the linked visualizer and the mini player |

While playing, the controller tops up a 0.3 s audio queue (the latency for
control changes), maps the device's played frame to the sounding bar for the
header, and feeds the analysed spectrum to every open visualizer. Camera
flights cruise at a steady speed, eased in on Play and out on Stop: the music
drives light, colour and pulses, never motion. The controller's timer fires
irregularly while synthesis runs, so each tick advances by the time measured
with `ns.uptime()`, and shaders extrapolate travel by its speed times
`inputs.age` (the seconds since values arrived) to move evenly on every
display frame. Full
synthesis costs about a fifth of one core at its busiest.

Tests: `tests/dnb.test.lua` (the drum & bass set, composition, synthesis,
visuals, the controller with a fake output, the native plugin),
`tests/dnb_arrangement.test.lua` (clip automation, cuts and rides, the
producer's moves in every style, forms and build kinds, filtered voices,
the whole-mix sweep, timeline clips),
`tests/dnb_plugins.test.lua` (the contract every style plugin keeps, style
switching, scene pinning, the mini player), `tests/plugins.test.lua` (the
framework), `tests/shader_view.test.lua`, `tests/window_chrome.test.lua`,
`tests/control_styles.test.lua` and `tests/fixed_size.test.lua`.
