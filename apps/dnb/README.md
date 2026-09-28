# Drum & Bass

An endless drum & bass DJ set. Every sound is synthesized in Lua: no samples,
no audio files — even the Amen break is recreated, kit and room, then played
the way jungle producers played it: a sped-up loop cut into 16th slices and
rearranged. Press Play and one seed plays a set that never repeats. Tracks
follow each other in Liquid, Jungle, Neurofunk and Rollers styles, in keys a
DJ could mix between. Each new track's drum intro is mixed under the outgoing
tune's chords. Lit pads (after the Logic Pro Drum Machine Designer) switch
parts and structure; fill bars shape the groove and sound live. Next Track
mixes into the next track of the set at the next bar line, and New Set starts
a new seed.

```sh
make run ARGS=apps/dnb
```

| File | Role |
|---|---|
| `Model.lua` | Parts and controls (the single source for the pads and fill bars), ranges and formatting |
| `models/Composer.lua` | The set: tracks with a style, key (harmonically mixed), mode and length; per track intro → build → drops and breakdowns → outro, with the next intro blended over the outgoing tune. Voice-led extended chords, key changes, half-time switch-ups, humanized two-step grooves, fills, Amen layers and chops, keys comping, arpeggios, a call-and-response lead, dub throws. `bar(n)` is a pure function of seed, bar and settings |
| `models/Amen.lua` | The recreated Amen break's four-bar pattern and slice bookkeeping |
| `models/Synth.lua` | Sample-accurate synthesis: one-shot drums, the Amen loop and its slice sampler, reese and sub bass with wobble filter and drive, pads, FM electric piano, stabs, arp plucks, a gliding lead, risers, ping-pong delay with throws, reverb, sidechain pump, soft clip |
| `models/Visuals.lua` | Spectrum smoothing, peak holds, kick and snare flashes, scene choice per section and phrase with crossfades, and the shader value layout |
| `services/AudioOutput.lua` | Speaker output through [AudioStream](../../src/plugins/audio/README.md) |
| `shaders/Visualizer.metal` | Six scenes rendered by `<ShaderView>`: synthwave spectrum horizon, ridge-line landscape flight, liquid metaballs, light trails, tunnel and a crystal kaleidoscope |
| `views/` | Window, stage, parts and controls templates |

The controller runs one display loop at 60 Hz. While playing, it tops up a
0.3 s audio queue (the latency for control changes), maps the device's played
frame to the sounding bar for the header, and feeds the analysed spectrum to
the shader. Full synthesis costs about a fifth of one core at its busiest.

Tests: `tests/dnb.test.lua` (set, composition, synthesis, visuals, controller
with a fake output, plugin), `tests/shader_view.test.lua`,
`tests/control_styles.test.lua` and `tests/fixed_size.test.lua`.
