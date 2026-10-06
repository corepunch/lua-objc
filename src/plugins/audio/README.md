# AudioStream native Lua plugin

Built by `make` as `build/AudioStream.dylib`. It is a stereo PCM output queue:
Lua synthesizes interleaved float frames and writes them into a lock-free
single-producer/single-consumer ring; an `AVAudioSourceNode` drains the ring
on the realtime audio thread. The audio thread never calls Lua, so synthesis
and composition stay in plain Lua that headless tests can run. The Drum &
Bass app (`apps/dnb`) is the client.

```lua
local App = require("App")
local audio = App.loadNativePlugin(assert(package.searchpath("AudioStream", package.cpath)), "AudioStream")
local stream = audio.open(44100, 13230)  -- sample rate, queue capacity in frames
audio.write(stream, samples, frames)     -- -> frames queued (never overwrites unplayed audio)
audio.space(stream)                      -- -> frames that can be queued now
assert(audio.start(stream))              -- or nil, error message
audio.pause(stream)                      -- keeps queued frames; start resumes seamlessly
audio.played(stream)                     -- -> frames played since open, underrun count
audio.spectrum(stream, 40)               -- -> 40 band levels 0…1, RMS of what just played
audio.analyze(samples, 44100, 40)        -- same analysis of a Lua sample table
audio.close(stream)                      -- also on GC
```

`samples` is a sequence of interleaved left/right numbers, clamped to ±1.
When the queue runs dry the device gets silence and the underrun count grows;
queued audio is never skipped, so the frame count from `played` maps exactly to
the producer's timeline, which is how apps sync visuals to what is audible.

`spectrum` keeps a mono copy of the last 2048 played frames (46 ms at 44.1 kHz)
and runs a Hann-windowed vDSP FFT on request. Bands are log-spaced from 30 Hz to
16 kHz; each is the band's peak power, from 0 at −78 dB to 1 at full scale.
`analyze` uses the same code on the last 2048 frames of a table, so tests can
check it against known signals.

The queue capacity is the latency between a parameter change and hearing it.
Producers refill it from a Lua timer; Lua timers run in the common run-loop
modes, so refills continue while a slider tracks the mouse. The code image stays
mapped until process exit because the render block is plugin code.

# AudioFile native Lua plugin

Built by `make` as `build/AudioFile.dylib`: reading, slicing and auditioning
sound files with AVAudioFile (WAV, AIFF, CAF, MP3, AAC, ALAC, FLAC). The
Slicer app (`apps/slicer`) is the client.

```lua
local file = App.loadNativePlugin(assert(package.searchpath("AudioFile", package.cpath)), "AudioFile")
file.info(path)                     -- {duration, frames, sampleRate, channels}, or nil, message
file.export(path, from, to, out)    -- seconds -> frames written to a 24-bit WAV, or nil, message
file.play(path, from, to, onEnd)    -- auditions a span; replaces what is playing
file.pause()                        -- keeps the position
file.resume()
file.stop()                         -- onEnd does not run
```

Slices keep the source's sample rate and channels. `onEnd()` runs on the
main thread once the span has been heard; a stopped or replaced audition
never reports an end. Audition uses one shared
AVAudioEngine that is stopped, not left idling, by `stop` and before each
new `play`.
