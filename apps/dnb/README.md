# Drum & Bass — an endless electronic music generator

Endless DJ sets in seven electronic styles, every sound synthesized in Lua:
no audio files. It works the way a tracker module does. A track plays on
**eight channels**; it carries its own **instruments** (patches) and its own
**drum loops**, rendered once and played by slice; and it is made of
**blocks**: authored loops (`trance.bass.024`, a four-bar hook, a drum
groove, a chord rhythm), each with tags and numbers, that the arranger picks
by tag and lays on one long canvas of four to five minutes. There are no
verses, builds or drops to fill in: a track is an energy curve, and the
layers and moves of a genre follow it. Press Play and one seed plays a set
that never repeats, each new track mixed under the outgoing tune.

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
- **its blocks**: a small palette of each role's blocks (two or three basses,
  a quiet and a loud drum loop, a hook and its variation), chosen by the
  flavour's `wants` and `avoid` tags and spread across the energy range,
  never the ones the track before had. They are authored data
  (`plugins/styles/<genre>/blocks.lua`, `library/blocks/common.lua`; see
  [BLOCKS.md](BLOCKS.md)): about 800 of them;
- **its drum kit**: the grooves are rendered on a kit of its own (a snare
  character, a retuned kick, hats and clap);
- **a tempo and a swing** within the flavour's range. A new track reaches
  its tempo through the blend, as a DJ rides the pitch fader;
- **a length and an energy curve**: four to five minutes, drawn from the
  genre's arc (a first peak, a valley, a higher second peak, a mix-out),
  with its anchors moved a little per track;
- **a key, a mode and a harmony**: a progression held for sixteen bars, then
  kept or swapped, and sometimes a key lift on the second peak.

## One canvas, no sections

`host/Canvas.lua` is the arranger. A track is eight-bar **phrases** carrying
an energy from the curve, and the arranger decides one phrase at a time:

- **which layers play.** A genre's layers enter in an order (drums, then
  bass and tops, then chords, melody…); the curve says how many are on. A
  breakdown (a fall from a peak) sends the drums and usually the bass out
  and keeps the harmony. The first and last sixteen bars keep to drums,
  tops and texture so tracks mix;
- **what each layer plays.** The block of its palette nearest in energy,
  held until the curve moves, with a swap now and then at sixteen bars.
  Blocks may exclude each other (`excludes`), and the foundation wins;
- **what happens at the edges.** Only where the genre uses them: a riser,
  a snare roll and an impact around a big rise (techno and jungle place
  none); a fill ending a phrase; the drums or bass dropping out of the last
  bars; a half-time phrase; a layer opening through a filter as it enters;
  the bass closing at the mix-out.

Changes land on phrase boundaries, so nothing enters off the grid. The
result is lanes of blocks (`host/Lanes.lua`, `host/Arrangement.lua`) and a
list of events ("Breakdown in 8 bars") for the timeline. A style tunes the
shape in its manifest's `arc` (`Canvas.defaults` lists every field), a
flavour overrides it. `docs/research/dance-music-arrangement.md` is what
the shapes are based on.

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
headline names the next event of the track.

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
break (`kit = "break"`, the Amen and others in `library/blocks/common.lua`) is
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
`flavours` (each its tempo and swing range, its channels, the patch each may
play and the tags of the blocks it `wants` or must `avoid`), its `harmony`,
its `arc`, its own patches and fills (`library`), its drum `kit` and `mix`.
Its blocks are the data file beside it, `blocks.lua`, which the host reads:
a plugin's sandbox has no `require`.

```lua
{id = "trance.bass.024", role = "bass", bars = 2, energy = 0.7, density = 0.6,
 tags = {"offbeat", "driving", "euphoric"}, flavours = {"uplifting", "tech"},
 notes = "2:0:1.6 6:0:1.6 10:0:1.6 14:0:1.6 | 2:0:1.6 6:7:1.6 10:0:1.6 14:4:1.6", octave = 1}
```

The host's [`Composer`](host/Composer.lua) writes each track's harmony,
fills and edits, has the canvas arrange it, and renders bar n from the
blocks under it. Lane blocks are plain data, never overlap, and point at
patterns by id (every authored block is a pattern, `host/Patterns.lua`), so
tests read the plan instead of rendering audio. A block may carry
automation, as a clip does: `level` fades it and `filter` sweeps a low-pass
or a high-pass over it; the channel's strip in the Synth rides it through
the bar.

Adding a genre is one folder and one line in
[`host/Styles.lua`](host/Styles.lua); adding a flavour is a table; adding
variety is more blocks.

**Visualizer plugins** (`plugins/visualizers/<id>/`) are declarative: a
title, symbol, the range of the track's energy the director shows them in, and a
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
| `library/` | The material every style shares: `Patches.lua`, `Fills.lua`, `blocks/common.lua`; `calibrate.lua` levels the patches |
| `BLOCKS.md`, `host/Blocks.lua` | The block contract: fields, tags, per-role content; the parser and the catalogue |
| `host/Library.lua` | The notation beats and notes are written in; patches and fills, a style's over the shared |
| `host/Canvas.lua` | The arranger: a track's length, energy curve and palette, and its layers, blocks and moves phrase by phrase |
| `host/Lanes.lua`, `host/Patterns.lua` | The lane builder (add, fill, cut, automate); the renderers that play a block into a bar |
| `host/Styles.lua`, `host/StyleKit.lua` | The style extension point and its host API: theory, the set and its tracks, the bar score |
| `host/Arrangement.lua`, `host/Composer.lua` | A track's phrases, events and lanes, checked and searchable; the composer every style shares, which writes a track's harmony, arranges it and renders bars |
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
blocks and how each role renders), `tests/dnb_blocks.test.lua` (the block
files of every genre and their quotas), `tests/dnb_arrangement.test.lua`
(the lane builder, the canvas: curve, palette, layers, moves in every
style, channel rides, timeline clips),
`tests/dnb_plugins.test.lua` (the contract every style plugin keeps, every
flavour rendered, track kits, style switching, scene pinning, the mini
player), `tests/plugins.test.lua` (the
framework), `tests/shader_view.test.lua`, `tests/window_chrome.test.lua`,
`tests/control_styles.test.lua` and `tests/fixed_size.test.lua`.
