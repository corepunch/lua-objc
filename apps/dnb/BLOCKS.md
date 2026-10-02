# Blocks

A track in apps/dnb is not written from a form. It is one long canvas of
4–5 minutes on up to eight channels, and each channel is a lane of
**blocks**: authored loops that the arranger picks by tag, number and
energy. This file is the contract for writing blocks. The arranger is
`host/Canvas.lua`, the parser is `host/Blocks.lua`, the check is
`./lua-objc --test tests/dnb_blocks.test.lua`.

Where blocks live:

- `plugins/styles/<genre>/blocks.lua` — returns a list of block tables for
  one genre (`dnb`, `techno`, `house`, `trance`, `dubstep`, `breakbeat`,
  `garage`).
- `library/blocks/common.lua` — blocks every genre may play (`common.*`).

## A block

```lua
{id = "trance.bass.024", role = "bass", bars = 2, energy = 0.7, density = 0.6,
 tags = {"offbeat", "driving", "euphoric"}, flavours = {"uplifting", "tech"},
 notes = "2:0:1.6 6:0:1.6 10:0:1.6 14:0:1.6 | 2:0:1.6 6:7:1.6 10:0:1.6 14:4:1.6", octave = 1}
```

| field | meaning |
|---|---|
| `id` | `<genre>.<role>.<nnn>`: genre folder name, role, a three-digit number unique to that genre and role. Numbers need not be consecutive. |
| `role` | one of `drums tops bass pad keys stab arp lead counter texture fx` |
| `bars` | 1–8, the loop length. A 4-bar hook is `bars = 4`. |
| `energy` | 0–1, how intense the block is *by itself* (a lone kick 0.2, the full groove 0.9). The arranger takes the block nearest the energy a moment wants, so a role needs blocks across the range. |
| `density` | 0–1, how busy it is (notes or onsets per bar, layers of percussion) |
| `brightness` | 0–1, optional (0.5). Sub 0, hats and risers 1. |
| `tags` | what it is, lower-case words with hyphens. Vocabulary below. |
| `flavours` | optional: the genre's flavour ids it fits. Leave it out when it suits the whole genre. |
| `excludes` | optional: tags it cannot share a phrase with (e.g. an `offbeat` bass excludes `rolling`) |

### Content by role

- **drums, tops** — `lanes` exactly as a beat in `library/Beats.lua`
  (`{"kick", "X...X...X...X..."}`; 16 steps a bar, `X` accent, `x` hit,
  `o` soft, `g` ghost, `|` between bars, `gain`, `when = "energy" |
  "complexity"`, `light = false` to keep a lane out of the light variant
  used by the first and last bars of a track, `div = 32`). The lanes cover
  `bars` bars. `drums` is the main kit loop (kick, snare, hats); `tops`
  is a second layer over it (hats, shakers, percussion, a break) and never
  needs its own kick. A record's break takes `kit = "break"` and `bpm`
  (see `break.amen`).
- **bass, lead, counter** — `notes`, `"step:pitch:length"` with bars split
  by `|`; pitch in scale steps (0 root, 2 third, 4 fifth, 7 octave, `b`/`#`
  bend a semitone); `~` slides into the note, `!` accents, `?` plays while
  Energy is up, `+` while Complexity is, `w3` a wobble rate. `follow =
  "chord"` (default) moves with the chord, `"key"` holds still. `octave`
  shifts by octaves. Lead blocks are the tune; a `counter` answers a lead.
- **pad, keys, stab** — `comp = "0:3 4:2! 10:4 | 0:16"`: `step:length` chord
  hits, bars split by `|` (`bars` must be at least as many as written; a
  shorter rhythm repeats). A pad may instead be `hold = true` (the chord sustains for
  as long as it lasts, which is what most pads do).
- **arp** — `order = {1,2,3,4,3,2}` (chord tones, 1 the lowest, higher
  numbers climb an octave), `rate` 1 | 2 | 4 (steps between notes), `gate`
  (note length as a share of the step), `mask = "XXxx"` (`X` always,
  `x` while Complexity is up, `.` rest; any length that divides 16 repeats
  across the bar), `octave` 0–2.
- **texture** — `voices = {0, 7}` semitones above the key's root, held
  `every` bars (default 4).
- **fx** — `kind = "riser" | "downlifter" | "impact" | "crash"`. A riser
  scales to whatever length the arranger gives it (`bars` is its usual
  length: 4 or 8); an impact lands on the first bar of a phrase.

## Tags the arranger understands

The arranger reads these; everything else is description that helps
selection by `wants` and `avoid` in the flavours.

- `halftime` — drums with the snare on beat 3 of the bar; the arranger may
  switch a track to one for a phrase.
- `mixable` — plays well alone and in a DJ mix: drums and tops for the
  first and last bars of a track (no tonal content, no dependence on a bass
  or a lead). Every genre needs several `mixable` drums blocks of low energy.
- `sparse` / `busy` — fewer / more notes than usual for the role.

Suggested vocabulary (use these words before inventing others):

- rhythm: `fourfloor` `twostep` `broken` `break` `shuffle` `offbeat`
  `rolling` `gallop` `syncopated` `straight` `driving` `minimal` `swung`
- bass: `sub` `reese` `acid` `pluck` `wobble` `stab` `walking` `pedal` `octave`
- melodic: `hook` `answer` `arpeggio` `stepwise` `leap` `vocal` `riff`
  `chordal` `held` `rhythmic` `ambient`
- mood: `dark` `euphoric` `warm` `tense` `dreamy` `aggressive` `hypnotic`
  `playful` `soulful` `bright` `deep` `melancholic`

## What a genre needs

Enough blocks that two tracks of one flavour rarely share a hook or a bass
line. Per genre, at least: drums 12 (energies from 0.2 to 1, at least 4
`mixable` below 0.5, at least 2 `halftime` where the genre has a half-time
feel), tops 5, bass 12, pad 4, keys 4, stab 5, arp 6, lead 10, counter 4,
texture 4, fx 8 (at least 2 risers where the genre uses risers, 2 impacts,
a downlifter). A genre that never uses risers (techno, minimal, jungle)
writes none and says so in a comment; the arranger then has none to place.
Spread `energy` and `density` over each role's range: a role whose blocks
all sit at 0.8 cannot be quiet. Bass lines and leads carry the genre's
character, so write them like a producer: every line should be playable
and sound intentional on its own and under a changing chord.

Write the flavour a block fits in `flavours` whenever it only suits some;
roughly a third of a flavour's blocks should be its own.
