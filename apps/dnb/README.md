# Drum & Bass

An endless drum & bass generator. Every sound is synthesized in Lua: no
samples, no audio files. Press Play and it composes and plays forever, opening
on a beat and dropping after eight bars. Lit pads (after the Logic Pro Drum
Machine Designer) switch parts and structure; fill bars shape the groove and
sound live; New Track draws a new key, progression, groove and bass line at the
next bar line.

```sh
make run ARGS=apps/dnb
```

| File | Role |
|---|---|
| `Model.lua` | Parts and controls (the single source for the pads and fill bars), ranges and formatting |
| `models/Composer.lua` | Seeded arranger: drum intro → build → 32-bar drop → breakdown → build, forever; two-step grooves, ghost notes, rolling bass motifs, minor progressions, fills. `bar(n)` is a pure function of seed, bar and settings |
| `models/Synth.lua` | Sample-accurate synthesis: one-shot drums, reese and sub bass with wobble filter and drive, pads, stabs, riser, ping-pong delay, reverb, sidechain pump, soft clip |
| `models/Visuals.lua` | Spectrum smoothing, peak holds, kick flashes and the shader value layout |
| `services/AudioOutput.lua` | Speaker output through [AudioStream](../../src/plugins/audio/README.md) |
| `shaders/Visualizer.metal` | Synthwave spectrum visualizer rendered by `<ShaderView>` |
| `views/` | Window, stage, parts and controls templates |

The controller runs one display loop at 60 Hz. While playing, it tops up a
0.3 s audio queue (the latency for control changes), maps the device's played
frame to the sounding bar for the header, and feeds the analysed spectrum to
the shader. Full synthesis costs about a tenth of one core.

Tests: `tests/dnb.test.lua` (composition, synthesis, controller with a fake
output, plugin), `tests/shader_view.test.lua` and `tests/control_styles.test.lua`.
