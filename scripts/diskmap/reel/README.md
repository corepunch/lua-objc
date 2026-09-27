# Diskmap showreel

A 30-second motion piece built from real Diskmap captures: the pages are cut
into components (the sunburst, list rows, stat cards, treemap tiles, the
File Types donut) and animated with springs, masked reveals, motion blur and
kinetic type. The score is synthesized from the same event list as the
animation, so every pop, slam and whoosh lands on the 120 BPM grid.

```sh
make diskmap-reel            # → build/Diskmap-Showreel.mov (about 8 minutes)
make diskmap-reel-captures   # refresh captures/ after a UI change
```

The output is 1920×1080, 30 fps, H.264 with AAC 256 kbps stereo audio. The
rendered movie is a build product and is not committed.

## Files

- `Timeline.swift` — the storyboard. Every event time sits on the beat grid
  (beat = 0.5 s, bar = 2 s); edit captions, timing and crops here.
- `Music.swift` — the score, generated from `Timeline.swift`'s event lists.
- `Core.swift` — easing and springs, type, SF Symbols, sprites, masks,
  particles.
- `main.swift` — motion-blurred rendering (five sub-frames per frame, 180°
  shutter), encoding, and the `import` step that turns a `--screenshot`
  capture into a window-only JPEG.
- `capture.sh` — captures each page in light and dark with
  `apps/diskmap/init.lua --showcase` and imports it.
- `captures/` — 2× window-only JPEGs (2880×1800) of the 1440×900 pt window.

## Crops

Components are cropped from the captures in window points (see `piece(…)` in
`Timeline.swift`). A layout change in Diskmap can move them: after
`make diskmap-reel-captures`, check stills before rendering the whole reel:

```sh
build/diskmap-reel stills scripts/diskmap/reel/captures /tmp 4.6,8.3,10.5,13.2,20.8
```
