# Diskmap showreel

A 30-second, 1080p motion piece built from real Diskmap captures, rendered
with the Reel module ([modules/reel](../../modules/reel/README.md)). Pages
are cut into components by view identifier (the sunburst, list rows, stat
cards, treemap cells, the File Types donut) and animated with springs,
masked reveals, motion blur and kinetic type. The score is synthesised from
the same timeline, so every pop, slam and whoosh lands on the 120 BPM grid.

```sh
make diskmap-reel            # → build/Diskmap-Showreel.mov (about 3 minutes)
make diskmap-reel-captures   # recapture after a UI change (opens Diskmap, about a minute)
./lua-objc reels/diskmap/init.lua stills /tmp 4.6,8.3,10.5,13.2,20.8
```

| File | Contents |
|---|---|
| `views/Reel.etlua` | Styles, the stage, the camera shake and the order of scenes |
| `views/*.etlua` | One template per scene, on the beat grid (beat = 0.5 s, bar = 2 s) |
| `shots.lua` | The bespoke wall-and-dive shot, drawn with the pen |
| `Score.lua` | The music: chords and groove, plus the picture's pops, slams and cues |
| `init.lua` | Reel data (kicks, logo ring, orbit, divider cues) and the render modes |
| `capture.lua` | Capture plan: every page in light and dark, in one `--showcase` Diskmap launch |
| `captures/` | Generated, not committed: window PNGs and layout dumps; `make diskmap-reel` makes them when missing |
