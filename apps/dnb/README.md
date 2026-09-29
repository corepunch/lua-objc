# Drum & Bass — an endless electronic music generator

Endless DJ sets in seven electronic styles, every sound synthesized in Lua:
no audio files. It works the way a tracker module does. A track plays on
**eight channels**; it carries its own **instruments** (patches) and its own
**drum loops**, rendered once and played by slice; and it is made of
**authored material** (grooves, breaks, fills, bass lines, hooks) that the
generator picks, varies and arranges. Press Play and one seed plays a set
that never repeats, each new intro mixed under the outgoing tune.

| Style | Flavours | Tempo |
|---|---|---|
| Drum & Bass | Liquid, Anthem, Jungle, Amen Tearout, Neurofunk, Rollers, Minimal, Halftime, Jump-Up, Atmospheric | 160–176 |
| Techno | Peak Time, Acid, Hypnotic, Industrial, Minimal, Melodic, Dub Techno | 118–140 |
| House | Deep, Classic, Disco, Piano, Organ, Tribal, Acid, French | 118–128 |
| Trance | Uplifting, Progressive, Psytrance, Acid, Tech, Goa, Dream | 132–145 |
| Dubstep | Deep, Brostep, Riddim, Melodic, Dub, Chillstep | 136–150 |
| Breakbeat | Big Beat, Nu Skool, Florida, Funky, Progressive, Electro, Rave | 120–140 |
| UK Garage | 2-Step, Speed Garage, Future Garage, Bassline, Dark Garage | 128–140 |

```sh
make run ARGS=apps/dnb
```

## What makes one track differ from the next

A flavour is a kind of record, not a shade of one tune: it says which
channels a track has and what each may play. A Minimal drum & bass track
has five channels and no chords; an Anthem has a lead, a voice that answers
it and a wall of pads. From its flavour and the set's seed every track
draws:

- **its channels**, eight at most, by role: `drums`, `tops` (a second loop:
  a break or percussion), `bass`, `pad`, `keys`, `stab`, `arp`, `lead`,
  `counter`, `texture`, `fx`. A channel a flavour gives a `chance` may sit a
  track out;
- **a patch for each pitched channel**, never the one the track before had
  there. There are some seventy (`library/Patches.lua`): reese, acid, FM,
  808, wobble and upright basses, saw, glass, choir and organ pads, electric
  pianos, plucked strings, leads that glide or sing;
- **its grooves**, authored as steps and rendered into loops on the track's
  own **drum kit** (a snare character, a retuned kick, hats and clap);
- **a tempo and a swing** within the flavour's range. A new track reaches
  its tempo through the blend, as a DJ rides the pitch fader;
- **one rhythm cell and one motif**. The hook repeats, answers and resolves
  the motif; the chords are struck on the cell; the arpeggio follows the
  motif's contour. Later drops vary the hook (an octave up, mirrored, with
  the leaps filled in) but keep its rhythm: it is the same tune;
- **a bass line**: an authored one, sometimes with its answers moved, or one
  written for the track (a rolling line, a 303, a wobble);
- **a key, a mode, a progression and a form**, as before.

`tests/dnb.test.lua` measures this: across sixteen tracks of any style no
two running share their instruments, and the basses, grooves, tempos, hooks
and bass lines all differ.

## The window

The visualizer fills the window, running under the Liquid Glass toolbar; the
now-playing cards, the arrangement strip and the sliders float over it in
glass. The **arrangement strip** has eight rows, one to a channel, each
named after what the playing track has on it ("Amen", "Reese", "Rhodes").
Clips scroll right to left past a fixed playhead and show the fade or filter
sweep riding them; beside the playhead each channel has a level meter; the
headline names the section to come.

**Groove**: Pitch moves the tempo a few percent either way, as a
turntable does, and the pitch of the drum loops with it. Energy and
Complexity let in the layers a groove marks for them, the notes a line marks
"?" and "+", and the break edits. Swing scales the track's own. **Sound**:
Filter, Wobble and Drive move the bass around its patch. **Mix**: faders
over the style's balance. The Style menu switches genre on the next bar
line; Next Track mixes into the next track; New Set starts a new seed; Mini
Player (`pip.enter`) shrinks the app into a floating 16:9 window.

## Drums: loops, slices and edits

A beat is written as lanes of steps (`host/Library.lua` documents the
notation):

```lua
{id = "dnb.twostep", name = "Two-Step", bars = 2, lanes = {
	{"kick", "X.........x.....|X.........x....."},
	{"snare", "....X.......X..."},
	{"hat", ".x.x.x.x.x.x.x.x", gain = 0.22, when = "energy"},
	{"ghost", ".......g.g.....g", when = "complexity"},
}}
```

`models/Drums.lua` renders it once into a loop on the track's kit, at the
track's tempo, with its swing and a drummer's drift baked in. A slice of the
loop holds everything that rang into that 16th. The drum channel plays the
loop by slice: in order, or jumping to any point of it, which is the
tracker's sample-offset effect. Fills and chops are edits of that kind:
a stuttered snare slice, the last beat backwards, a retrigger in 32nds, the
tape slowing to half speed, a beat swapped in from elsewhere. A record's
break (`kit = "break"`, the Amen and five more in `library/Beats.lua`) is
rendered at the record's tempo on a 1960s kit through a room, and sped up
to the track's. Loops are prepared a little at a time, bars before they are
needed, so that no display frame waits on one.

## Instruments

Every pitched channel plays one engine, `models/Instrument.lua`; a patch is
plain data:

```lua
{id = "bass.acid", name = "Acid 303", role = "bass", mono = true, glide = 0.045,
	osc = {{wave = "saw"}},
	filter = {cutoff = 420, resonance = 0.16, env = 3.2, decay = 0.1},
	amp = {attack = 0.003, decay = 0.3, sustain = 0.7, release = 0.03}, drive = 0.45, level = 0.746},
```

Waves are saw, square, pulse, triangle, sine (with two-operator FM), noise
and a plucked string. `level` is calibrated, so patches of one role are
equally loud: after changing a patch run
`./lua-objc apps/dnb/library/calibrate.lua` and copy its level.

## Plugins

Styles and visualizer scenes are plugins, built on the framework's
[`Plugins`](../../lua/Plugins.lua) module (see
[ARCHITECTURE.md](../../ARCHITECTURE.md#plugins-luapluginslua)). Each is a
folder whose `init.lua` returns a manifest. It runs isolated: pure standard
libraries only, with everything else coming from a read-only host API.

**Style plugins** (`plugins/styles/<id>/`) are data. A manifest declares its
`flavours` (each its tempo and swing range, its channels and what each may
play), its `harmony`, its own `library` of beats and lines, its drum `kit`
and `mix`, and its `plan`: what each role plays in each section.

```lua
plan = {
	drop = {pad = {"pad.chords", from = 16}, lead = {{"lead.hook", from = 16, last = 0}, {"lead.hook", cycle = 1}}},
	breakdown = {bass = false},
}
```

An entry is a pattern id with where it plays: `from` and `to` in bars (or
"half", "phrase", "blend"), `cycle` and `last` for the drops it plays in,
`every` for a bar every so many, `keep` to hold a part to its entry. The
plan lies over the one every style shares (`StyleKit.plan`), and a flavour's
over its style's. The host's [`Composer`](host/Composer.lua) writes each
track's material and builds its [`Arrangement`](host/Arrangement.lua) once,
from the seed alone, and renders bar n from the blocks under it. Blocks are
plain data, never overlap in a lane, and point at patterns by id, so tests
read the plan instead of rendering audio. A block may carry automation, as
a clip does: `level` fades it and `filter` sweeps a low-pass or a high-pass
over it; the channel's strip in the Synth rides it through the bar.

After the plan come the producer's moves (`StyleKit.produce`), drawn from
the track's seed: parts join a phrase or two late and leave early, a phrase
ends on a fill or with the drums or the bass pulled out of its last bar, the
drums open through the intro, the bass is teased under a build, and the
outro sheds parts for the next track to mix over.

No two tracks take the same road. Each draws its form from the seed: how it
reaches the first drop (a build, straight out of the intro, or by way of a
melodic passage), what joins one drop to the next (a breakdown and a build,
a build alone, a breakdown the drop slams out of, or nothing: a double
drop), and how long each section runs, in whole eight-bar phrases so that
tracks still line up in the mix. A build winds up in one of four ways: a
snare roll, a kick roll, the drop's groove opening through a filter, or the
drums gone under the riser. A style weights these in its set's `form`, a
flavour in its own, and the same seed gives each style different forms.
Adding a genre is one folder and one line in
[`host/Styles.lua`](host/Styles.lua); adding a flavour, a groove or a patch
is a table.

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
| `Model.lua` | The roles a channel can have, their families, and the controls (the single source for the sliders) |
| `Controller.lua` | Window, transport, Style and Scene menus, the mini player, and the 60 Hz display loop |
| `library/` | The authored material every style shares: `Patches.lua`, `Beats.lua` (breaks and fills), `Lines.lua`, `Hooks.lua`; `calibrate.lua` levels the patches |
| `host/Library.lua` | The notation beats, lines and hooks are written in; a style's library over the shared one |
| `host/Motif.lua` | What the generator writes itself: rhythm cells, motifs and their development into hooks, bass lines, comping, arpeggios |
| `host/Styles.lua`, `host/StyleKit.lua` | The style extension point and its host API: theory, the set and its tracks, the lane builder, the plan, the producer's moves, the shared patterns and the bar score |
| `host/Arrangement.lua`, `host/Composer.lua` | A track's plan of sections and lanes, checked and searchable; the composer every style shares, which writes a track's material, arranges it and renders bars |
| `host/Visualizers.lua` | The visualizer extension point, the program it links and the draws that show a scene on a layer |
| `plugins/styles/*` | Drum & Bass, Techno, House, Trance, Dubstep, Breakbeat, UK Garage |
| `plugins/visualizers/*` | Synthwave Horizon, Valley Flight, Solar System, Liquid Chrome, Light Trails, Tunnel, Crystals |
| `models/Drums.lua` | The kit, designed per style and voiced anew for every track, and the loops rendered from beats |
| `models/Instrument.lua` | The patch-driven voice every pitched channel plays |
| `models/Synth.lua` | The player: bars to events, slices and voices on eight channel strips, sidechain pump, ping-pong delay with throws, reverb, soft clip |
| `models/Calibration.lua` | How loud a patch plays its role's phrase, and the level each role is held to |
| `models/Timeline.lua`, `views/Timeline.etlua`, `shaders/Timeline.metal` | The arrangement strip: eight rows, instanced clips, channel meters and the headline |
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
display frame. Synthesis
costs between an eighth and a fifth of one core at 44.1 kHz.

Tests: `tests/dnb.test.lua` (the set and its channels, variety across a
set, material, composition, synthesis, visuals, the controller with a fake
output, the timeline, the native plugin), `tests/dnb_library.test.lua` (the
notation, every patch and its loudness, the instrument, kits and loops,
motifs and their development), `tests/dnb_arrangement.test.lua` (the lane
builder, the plan, the producer's moves in every style, forms and build
kinds, channel rides, timeline clips),
`tests/dnb_plugins.test.lua` (the contract every style plugin keeps, every
flavour rendered, track kits, style switching, scene pinning, the mini
player), `tests/plugins.test.lua` (the
framework), `tests/shader_view.test.lua`, `tests/window_chrome.test.lua`,
`tests/control_styles.test.lua` and `tests/fixed_size.test.lua`.
