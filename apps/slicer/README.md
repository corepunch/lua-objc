# Slicer

Cuts a sound file into samples on a 140 BPM grid.

```sh
make
./lua-objc apps/slicer                 # then Open… or drop a file on the window
./lua-objc apps/slicer ~/Music/break.wav
```

- Click the waveform to place a cut on the nearest grid line (the toolbar
  picks 1/4, 1/8, 1/16, 1/32 or Off). Drag a cut to move it along the grid.
- Click a cut to select it; Delete removes it, ← → step between cuts.
- Play (Space, ⌘⇧P) plays the selected slice with a moving playhead; while
  playing the button is Pause, and Play again resumes. Escape (⌘.) stops.
- Scroll up/down (or pinch) over the waveform to zoom around the pointer;
  Zoom In/Out (⌘= / ⌘-) doubles or halves it. Scroll sideways when zoomed.
- Undo/Redo (⌘Z / ⌘⇧Z) cover adding, moving and deleting cuts.
- Export (⌘E) writes every slice into a folder as `<name> 01.wav`, … —
  24-bit WAV at the source's rate and channels — and shows them in the Finder.

The waveform is the framework's `<Waveform>` tag; files are read and written
by the `AudioFile` plugin (`src/plugins/audio`).
