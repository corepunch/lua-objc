# How dance music is actually arranged: research for a procedural track generator

Scope: DnB (liquid, neurofunk, jungle, jump-up, dancefloor), breakbeat, house (deep, tech, progressive, acid), techno (minimal, peak, hypnotic, dub), trance (uplifting, progressive, psy), UK garage/2-step, dubstep (brostep, deep/140).

Provenance legend: **[S]** = stated in a fetched source (URLs at bottom). **[K]** = producer/DJ practice from general domain knowledge, not directly confirmed by a fetched page; treat as defaults to tune by ear. Bar counts quoted from tutorials are *templates*; real tracks deviate.

---

## 1. Cross-genre principles

1. **Everything is phrase-aligned.** The 8-bar phrase is the base unit; 16 and 32 are the structural units; 64 is a "half-section". DJs count phrases, so a 24-bar section "throws off every blend" [S tracksensei, Mixed In Key]. Rule of thumb [S]: change something small every 8 bars, something bigger every 16, shift sections every 32.
2. **Two kinds of arrangement, and they are not the same thing.**
   - *Song-shaped* (DnB dancefloor/liquid, dubstep, uplifting trance, big-room house): intro / build / drop / breakdown / build / drop / outro, with risers and silence-before-drop.
   - *Loop-evolution / plateau-shaped* (techno, minimal, deep/tech house, psytrance, jungle, dub techno): no real buildup. A loop runs; each 16/32-bar block adds or removes one element; filters, reverb sends, and EQ drift slowly. "Techno builds in plateaus: each 32-bar block adds or subtracts one element, the level holds until the next boundary" [S tracksensei]. Subtraction beats addition: dropping the kick for 8 bars makes more tension than any riser [S].
   A generator should treat "has riser buildup" as a per-genre probability, not a default.
3. **DJ intro/outro are mix tools, not music.** Intro/outro of 16-64 bars of drums/percussion only, no melodic or harmonic content (key-clash safe). Under 16 bars blocks beatmatching [S]. 32 bars is standard (tech house, techno, DnB), 64 for trance/techno/psy. Outro mirrors the intro: strip melodic layers first, then bass, leave drums.
4. **Tension is mostly removal.** "Pros build tension by *removing* elements. Silence in the low end is an arrangement tool" [S Myloops trance]. Typical: remove kick+bass 2-4 bars at bar 16 of a 32-bar drop to "reset the ear" [S]; kick-out 8-16 bars in a techno reduction [S].
5. **Second peak > first peak.** Second drop adds layers, a different bass patch/character, or a key lift (trance) [S EDMProd/KAN/Myloops]. Identical second drops are a named mistake [S].
6. **Variation lives in processing, not notes** (techno/hypnotic): automate one parameter (filter cutoff, reverb, delay feedback) over 16-32 bars before a boundary; one crash or reversed cymbal per 32-bar transition max [S tracksensei].
7. **Transitions are small and located at the end of a phrase**: last 1-2 bars (fill, snare roll, reverse crash, 1-beat silence) then an impact/crash on bar 1 of the next phrase. [S/K]
8. **Low end is monophonic and exclusive.** One sub voice at a time; kick and sub/bass sidechained or time-split. Never layer two basslines in the sub range; swap rather than stack. [K, consistent with S "kept mono, sidechain linked to kick"]
9. **Peaking too early is the standard error** (energy at bar 1 leaves nowhere to climb) [S]. Overly melodic breakdowns break DJ momentum in techno [S].
10. **Total length** for DJ tools is 5-8 minutes, i.e. a lot of bars. Radio edits (3-4 min) do not apply to the target use. At 174 BPM, 32 bars = 44 s; at 128 BPM, 32 bars = 60 s; at 140, 32 bars = 55 s [S].

Bars to seconds: `seconds = bars * 4 * 60 / bpm`.

---

## 2. Per-genre facts

Columns used in each section: tempo, length, buildup?, phrase unit, components, layer map, pairs/exclusions, harmony.

### 2.1 Drum & Bass (general, 5-7 min)

- **Tempo** 170-180, mode 174-175 [S EDMProd, Beatportal "174 sweet spot"]. Always 4/4, snare on 2 and 4 *at full-time 174* (felt as half-time 87).
- **Template** [S KAN, EDMProd, Beatportal]: Intro 32 / Build 16 / Drop 1 64 (as 2x32) / Mid 16-32 / Breakdown 32 (often drumless) / Build 16 / Drop 2 64 / Outro 32 = about 270-310 bars = 6.2-7 min at 174. Beatportal's simpler time-based form: intro 0:00-0:45, build 0:45-1:00, drop 1:00-2:00, breakdown 2:00-2:30, drop 2 2:30-3:30, outro 3:30-4:00.
- **Phrase unit**: 16 bars for liquid (a track is built from 16-bar blocks) [S]; 32-bar half-drops generally; 8-bar bass/fill changes inside.
- **Buildup**: yes in dancefloor/neuro/jump-up (white-noise riser, accelerating snare roll, filter opening, drum intensification, 8-16 bars) [S]. Liquid often "builds" by filtering and adding strings/vocals rather than a noise riser. [K]
- **Drum 2-step core**: kick on 1 and the "and" of 3 (some use kick 1 and 3), snare on 2 and 4, hats filling eighths/sixteenths, ghost snares, a layered top-loop/break [S Beatportal/EDMProd]. Full 2-step bar: K . . . S . . . | . . K . S . . . roughly (16ths: K at 0 and 10, S at 4 and 12).
- **Bass layers** [S Beatportal]: sub sine (mono, LP ~80 Hz, sidechained), mid bass (saw/FM + distortion + LFO), reese (detuned saws). Key range D#1 to G#1; E/F/F# minor [S]. F minor most common for liquid [S].
- **Fills**: snare roll / drum fill in last bar of 8/16, crash on the downbeat.
- **Half-time switch**: drop played at 87 feel (snare on beat 3 of each bar... i.e. every other 2-step snare) used in neurofunk/darkstep as a variant drop section [S "half-time drops that punctuate builds" neurofunk summary].

#### Subgenres

| Subgenre | Tempo | Drum character | Bass | Harmony / hooks | Structure notes |
|---|---|---|---|---|---|
| **Liquid** | 170-176 (174) | Snappier, softer samples, higher in spectrum; ghost hits; shaker/hat loops; rides | Sine sub with light saturation, melodic bass notes ("composition over sound design") | Soulful piano chops, pads, vocals (sampled/featured), counter-melodies; F minor; major or minor, jazzy 7th/9th chords | 16-bar blocks; intro/breakdown 1, build 1, 3-6 drop variants (new melodic layers each time, not repeats), breakdown 2, outro 1-2 sections [S]; long atmospheric breakdowns |
| **Neurofunk** | 172-176 | Intricate, heavily processed breaks, rapid layered hats, ghost snares, polyrhythmic percussion | Reese + distorted, long drawn-out notes with subtle movement or one-note rhythm; bass timbre switches between sections | Minor, Phrygian/Locrian, root repetition, atonal FX; dark pads, FX | 16-32 bar loops; Intro 16-32 (pads/ambience, no drums), Breakdown 16, Drop A 16-32, Breakdown 2 16-32 (drums out), Drop B 16-32 with *different bass character* [S]. Breakdown = beat loop + pitched perc loop + impact + reverse noise (8 bars) then synth pluck with reverb-wet automation; build drop first then work backward [S Loopmasters] |
| **Jump-up** | 172-178 | Punchy kick/snare, bouncy, simple | Heavily distorted fast-moving reese/mid bass, call-and-response one-bar bass phrases | Minimal harmony; hooks are bass riffs and MC-style vocal shouts/samples | High-energy drops, short intro, repeated 8-bar bass phrase |
| **Dancefloor** | 172-176 | "Really punchy kick with weight and very heavy bright snare" | Powerful prominent bass | Pop-friendly progressions, catchy leads, vocals | Strong repeating loops, heavy layering, classic template with big build [S EDMProd] |
| **Minimal/deep DnB** | 172-176 | Reduced percussion | Clean sine, pentatonic bass notes | Short stabby synths | Restrained, groove-focused, sparse |
| **Jungle** | see 2.2 | | | | |

- **Pairs**: liquid = pads + piano + vocal + soft bass; neuro = reese + distorted FX + sparse dark pad + hard drums. Liquid and heavy distorted reese rarely co-occur. Rolling bass and hard half-time drop are not combined in the same bar.
- **Layer-in order (typical drop-based DnB)**: drums (kick/snare/hat) -> pad/atmos -> (build: noise riser, roll, filter open) -> bass + full drums + lead/stab -> (mid section: change bass, add counter-melody) -> breakdown (drums removed, pad/vocal/melody) -> re-build -> drop 2 (extra layer, new bass, more percussion) -> outro (drums only).

### 2.2 Jungle / breakbeat

- **Tempo**: 160-180; classic 165-170; darkcore 174-180; soulful ~160 [S MusicProductionWiki, vibesdj].
- **Length**: 5-7 min [S]; DJ-tool jungle often 4-6.
- **Buildup**: mostly *no riser build*. Sections defined by how busy the break is: dense chopped passages alternate with sparse bass-led breakdowns [S]. A "build" exists as 8-16 bars adding bass and stabs [S].
- **Template** [S MusicProductionWiki]: Intro 16-32 (break only) / Build 8-16 / Drop 16-32 / Breakdown 8-16 / Reintro 8 (vocals) / Drop 2 16-32 (variations) / Outro 16-32 (break-only exit).
- **Phrase**: 8 and 16; the break itself is a 1- or 2-bar pattern re-sequenced with a variation every 4 and a fill every 8.
- **Components**: Amen/Think/Funky Drummer/"Apache" break sliced and resequenced (pitched +2 to +4 semitones for aggression), hat flutter, ghost notes (hit-by-hit layering also used); sub sine below 80 Hz, often long sustained or reggae-style one-bar phrases; reese mid layer (detuned saw +/-7-12 cents, 80-400 Hz) for darker styles; ragga/dancehall vocal toasts; soul/jazz chops, horn stabs; horror dialogue; pads, vinyl crackle, reverse cymbals [S].
- **Swing**: ~8-12% on hats to keep break pocket [S].
- **Harmony**: derived from samples; minor, dub/reggae feel; bass notes mostly root + fifth + b7. [K]
- **Breakbeat (non-jungle: big beat, breakstep, nu-skool)** [K]: 120-140 BPM, break in 4/4 with kick on 1 and 3 and snare on 2 and 4 syncopated; arrangement closer to house/dubstep drop forms; breakstep (~130-140) is garage-derived with broken kick [S Wikipedia link].

### 2.3 House

Common: 4-on-the-floor kick, clap/snare on 2 and 4, offbeat open hat, closed hats/shaker on 16ths; 118-130 BPM.

| | Deep house | Tech house | Progressive house | Acid house |
|---|---|---|---|---|
| Tempo | 118-124 | 124-128 (126 sweet spot) [S] | 122-128 (126-128 typical) [S] | 120-130 |
| Length | 6-8 min | 6-7 min | 7-9 min [S] | 6-8 |
| Buildup | Rarely; "drops" are layer returns; short 8-bar breaks | Beatless breakdown then drop is typical; 8-bar breakdown/build [S] | Yes but gentle: 8-16-bar build with arp/filter/noise [S] | Little; the 303 filter sweep is the build |
| Phrase | 8/16 | 8/16, drop in A/B/C/D 8-bar parts [S] | 4/8/16; new sound every 8 bars [S] | 8/16 |
| Bass | muted/warm sub or offbeat pluck, jazzy walking, Rhodes-style bass | Rolling short bass, LP ~150 Hz, glide/legato, groove first [S] | Rolling or offbeat bass, arps | 303 acid line, resonant filter automated, accent+slide |
| Chords | jazz 7ths/9ths, Rhodes, organ stabs, soulful pads | Stabs (minor), vocal chops | I-V-vi-IV, vi-IV-I-V, I-VI-IV-V [S]; big pads, plucks, supersaw-lite lead | Minor pentatonic riff; chord stabs sparse |
| Keys | F, F#, G minor, A minor [S for tech] | F/F#/G minor [S] | minor, anthemic |
| Vocals | soulful sample, spoken loops | chopped one-liners, processed | verses/hooks in full-length | shouts, samples |

- **Deep house reference form** [S Mixed In Key, "4004 - Fanta Club"]: Intro 32 / BD 8 / Drop 24 / BD 16 / Drop 24 / BD 8 / Drop 24 / Bridge 16 / Drop 24 / Outro 8. Note: **24-bar drops** with short 8-16 breakdowns, i.e. house sections are not always powers of two but still multiples of 8. Regular repeated drops with "sections preceding each drop designed to subtly increase drama".
- **Tech house form** [S EDMProd, NI]: Intro 16 + Intro 2 16 (usually 32 total DJ intro) / Breakdown-build 8 / Drop 32 as A-B-C-D 8-bar variations; tension by removing the last bar of kicks before a section [S].
- **Progressive**: Intro 8-16 / Verse 16-32 / Build 8-16 / Drop 16-32 (16 min first drop, often 32 second) / Breakdown 8-16 / Outro 8-16 [S]; DJ intro/outro 16/32; "gradually increase drum complexity", alternate lead instruments.
- **Layer order (house)**: kick -> hat/offbeat hat -> clap/perc -> bass -> chords/stab -> vocal chop -> lead/pad. Out: reverse. Mid-track: kick out for 8 with pad+vocal, then everything back (the "house drop").
- **Exclusions**: 303 acid line and busy melodic lead do not run together (the acid line *is* the lead); deep-house jazz chords with distorted acid.

### 2.4 Techno

- **Tempo**: peak-time 128-135 (EDMProd says 120-135 in parts), raw/deep/hypnotic 130-140; minimal 125-132; dub techno 118-125 [S EDMProd, tracksensei: 128-135]. 
- **Length**: 6 min = about 195 bars at 130 [S]; 6-9 min typical.
- **Buildup**: **no**, except peak-time techno which allows a 8-16 bar riser/snare roll into a re-entry. Minimal/hypnotic/dub: none; evolve by layering/subtracting [S].
- **Phrases**: 32-bar blocks are the plateau; 8-bar changes of processing; 16-bar mid events [S]. EDMProd template: DJ Intro 16-32 / Breakdown 16-32 / Drop 16-32 / Drop variation 16-32 / Breakdown 16-32 / Drop 16-32 / Outro 16-32, variations every 8 bars minimum [S].
- **6-minute map at 130 BPM** [S tracksensei]: 1-32 drums (kick/hats/filtered loop) / 33-64 bass enters / 65-96 stab joins / 97-128 reduction (kick-out 8-16) / 129-160 peak = everything + one extra percussion layer / 161-192 outro (mirror intro, 32-64 bars).
- **Components**: 4/4 kick (909 or distorted), offbeat open hat, closed 16ths, clap/rim on 2 and 4 or off-grid, shaker, ride, tom/conga perc loops, noise hits; sub or arpeggiated bass in E0-E1 [S], rumble (reverb-tail kick low-passed, "rumble bass" in peak-time), acid line (raw/deep), chord stab with delay (dub), hypnotic one-note drones; pads/noise textures; FX sweeps, a single crash per 32 bars.
- **Subgenres**:
  - *Minimal*: sparse clicks/rimshots, sub kick-bass, micro-edits every 4/8 bars, long filter drift, loops of 1-2 bars, high swing on perc. No pads.
  - *Peak-time*: punchy modern percussion, layered digital synths, prominent FX sweeps, more obvious variation, rumble bass, hooks (single-note lead/stab) [S].
  - *Hypnotic/raw/deep*: 909, acid bass, heavy modulation, "longer repetitious arrangements with slow movement", underproduced [S].
  - *Dub techno*: chord stab (minor 7th, one chord) heavy delay + reverb throw, rumbling kick, noisy texture/vinyl hiss; arrangement = the delay send level and filter cutoff; chord *never* changes for 32+ bars. [K]
- **Harmony**: "You don't have to stick to a traditional scale" [S]; mostly one-note/minor, root-pedal with 1-2 chord colors (Phrygian b2). Key-agnostic percussion.
- **Mutually exclusive**: busy melody + minimal; riser + hypnotic; pad wash + dub stab at same time (both fill the reverb space).

### 2.5 Trance

| | Uplifting | Progressive | Psytrance |
|---|---|---|---|
| Tempo | 136-140 (138) [S] | 125-135 | 140-150 (145) [S] |
| Length | 6:45-8:30 (320-420 bars) [S] | 7-9 min | 7-10 min [S] |
| Buildup | **Yes: 16-32 bars**, three layers (pitched sweep + noise riser + accelerating snare roll) [S] | Gentle 16-bar filter/arp build | **No**: minimal breakdowns, incremental modulation [S] |
| Phrase | 32 | 16/32 | 16/32, 64 |

- **Uplifting skeleton** [S Myloops, 8 min @ 132-140]: DJ intro 32-64 / First groove 32 / First breakdown 16-32 (tease theme) / Interim drop 32 / **Main breakdown 32-64 (the song)** / Riser 8-16 / Main drop 32 (mini-break of kick+bass 2-4 bars around bar 16) / Outro 32-64. Intro/outro = drums and bass, no melodic commitment [S]. Keep main drop short (32-64 bars) [S]. Key lift (usually +1 or +2 semitones) in final drop [S].
- **Components**: 4-on-floor kick, offbeat bass (classic) or 16th rolling bass sidechained (modern) [S], offbeat open hat, clap/snare, snare roll, plucks/arps (16th, 1/8 dotted), supersaw chords + supersaw lead (the hook), piano breakdown, female vocal (ethereal), pads, white-noise risers, reverse cymbals, impacts.
- **Harmony**: minor (A/F#/G/C minor, E minor); i-VI-III-VII, i-VI-VII, vi-IV-I-V, 4 bars per chord or 1 bar per chord at 16-bar loop; melody built from chord tones; the chord loop runs 8 or 16 bars.
- **Progressive trance**: longer layering, arp-led, no vocal or sparse, 32-bar plateaus (techno-like).
- **Psytrance**: tight kick, rolling 1/16 bass (3 notes: root + octave + b7 offbeats), single-note patterns with velocity/length variation [S], acid-style leads/zaps, sidechain release 80-120 ms at 145 [S], wide noise/atmospheres; arrangement by adding/removing percussion and fx every 16 bars; a 16-bar mini-break; no riser.
- **Pairs**: supersaw lead + piano breakdown; arp + pluck; rolling bass + 16th hats. Exclusive: offbeat bass vs rolling-16th bass (choose one per track).

### 2.6 UK garage / 2-step

- **Tempo**: 130-138 (UKG/2-step typical 130-135 [K]); MusicRadar demo 127 [S]; speed garage 130-135; future garage 130-140.
- **Length**: 3.5-5 min (vocal-based), DJ-edits 5-6 [K].
- **Buildup**: Not really; "drops" are returning the bass/kick after a short drum+vocal break; sections 8/16 bars. [K]
- **Rhythm** [S MusicRadar, Wikipedia]: 2-step: kick on 1 and the "and" of 3 (some versions kick on 1 and 3 and snare on 3 / clap on 2 and 4), skipped kicks, shuffled hats, off-beat percussion, triplet rhythm; heavy swing (shuffle ~55-62%) on hats and perc; rimshots/woodblocks scattered; ghost kicks.
- **Components**: syncopated "weighty" bass (reese/sub/organ or 808 hits) above sub, synth stabs, chopped R&B vocals (pitched up, formant-shifted, rhythmically fragmented), pads, Rhodes chords, organ stabs, dub-style FX sweeps. Bass is syncopated, *not* rolling. [S/K]
- **Harmony**: minor 7th/9th chords, Rhodes, "pretty" chords (i-VII-VI), vocal hook melody; sub-bass root with chord stabs on off-beats.
- **Phrase**: 8 bars; vocal phrase 4 or 8; verse-chorus structure is acceptable here (the only genre in this list with real verse/chorus) [K].
- **Future garage** [K]: 130-140, half-time-ish snare, reverb-heavy pads, pitched vocal, sparse; no builds.

### 2.7 Dubstep

| | Deep / UK 140 | Brostep / riddim |
|---|---|---|
| Tempo | 138-142 (140) [S] | 140-150 (140 half-time felt as 70) |
| Length | 5-6 min [S]; deep 4-6 | 3:30-5:30 |
| Buildup | rarely; strategic silence 1-2 bars; filtered bass reveal [S] | yes: 8-16 bars, riser + snare roll + vocal call + silence |
| Phrase | 8 [S EDMProd: 8-bar increments] | 8/16 drops 16-32 |

- **Template** [S KAN]: Intro 32 / Build 16 / Drop 32 (about 55 s) / Mid 16-32 / Breakdown 32 / Build 16 / Drop 2 32 / Outro 32 = about 190-200 bars = 5.4-5.8 min at 140. Mixed in Key's 140-BPM remix: 16/16/16/16/16/40/16/16/16 (many 16-bar sections) [S].
- **Half-time drum**: kick on 1 (optional ghost on and-of-2), snare on beat 3 (of each bar) [S]; deep dubstep: claps/rimshots rather than large snares, 2-step shuffled hats, shaker, ride [S EDMProd]; brostep: huge snares.
- **Bass**: sub (FM/sine) + mid-bass 100-800 Hz wobble/growl/screech as fills and drop hook [S]; vary bass patches across drops; vary bass design or drum fills every 8 bars; in deep dubstep: sub-heavy, minimal, E minor is common [S]; reveal the wobble only at the drop [S].
- **Pitfalls** [S]: drops over 48 bars without variation; identical second drop; sparse breakdown 48+ bars; tempo drift in half-time sections.
- **Harmony**: E/F/G minor, single sub-pitch with chromatic mid bass; pads in breakdown (deep: dark pads, vocal chop, ambient). 
- **Exclusive**: brostep chunky snare + deep-dub rimshot (pick one); rolling DnB-style bass; 4/4 kick.

---

## 3. Component taxonomy, roles, and suggested tag vocabulary

### 3.1 Taxonomy (role -> sub-types -> function)

| Role group | Sub-types | Function | Typical lifetime |
|---|---|---|---|
| **kick** | 4/4 kick, 2-step kick, half-time kick, break-kick, rumble | the grid; always the first element in DJ intros | present nearly everywhere; removed 2-16 bars as a *move* |
| **snare / clap** | snare 2&4, half-time snare (3), clap, rim, ghost snares, snare roll | backbeat; roll = build | enters with kick or 8 later; roll = last 1-4 bars |
| **hats** | closed 8th/16th, offbeat open hat, shaker, ride, hat flutter | groove, swing, density control (the cheapest density dial) | enters at bar 1-9; densify at drops |
| **percussion loops** | tops loop, conga/tom loop, melodic perc, noise perc, break (amen etc.) | texture, energy, variation | added/removed every 8/16 |
| **break** | full break loop (jungle), chopped break, break fill | whole drum part in jungle/breakbeat; replaces kick+snare+hats | exclusive with programmed 2-step kick/snare in same section |
| **bass** | sub sine, reese, rolling 16th, offbeat bass, acid 303, pluck bass, stab bass, wobble/growl, 808, rumble | the low-end identity; **one active at a time** (+ sub pair) | enter at drop or after 32 bars; swap at 8/16 |
| **chords/stabs** | stab, organ, Rhodes, pad chords, supersaw chords, dub chord | harmony; hook in house/dub | enter 32 bars in; remove for breakdown or keep as sole content |
| **pads/drones** | pad, string, drone, choir | harmony in breakdown, space | intro/breakdown, quiet under drop |
| **arp/sequence** | arp, pluck seq, acid sequence, 16th gate | forward motion, melodic movement | middle of plateau |
| **lead/hook** | lead, supersaw lead, piano, whistle, bleep, vocal hook | memorable melody | drops, breakdowns (theme teased) |
| **vocal** | chop, phrase, adlib/shout, spoken, ragga toast, dialogue | identity, call-and-response | sparse; 1 per 8-16 bars |
| **fx-transition** | riser, noise sweep, reverse cymbal, downlifter, impact/boom, crash, snare roll, silence | marks a boundary; at last 1-8 bars | boundaries only |
| **atmosphere/texture** | noise bed, vinyl, field recording, reverb tail, rain, tape hiss | fills space, links sections | continuous, low level |

### 3.2 Suggested tag vocabulary per clip (loop)

Based on Splice/Loopmasters/Ableton-pack metadata: Splice filters by genre, instrument (keys, drums, bass...), key, BPM, type (loop vs one-shot), and mood/style tags such as "dark", "bright", "energetic", "uplifting", "tense", "nostalgic", "lo-fi", "melody", "analog" [S Splice]. Loopmasters filenames embed BPM, key and role (e.g. `SNT2_170_E_FX_Percussion_42`: pack, bpm, key, category, subcategory, index) [S Loopmasters].

```
clip {
  id, name,
  role:        kick|snare|hats|perc|break|bass|chords|pad|arp|lead|vocal|fx|atmos|fill
  sub:         free string (sub|reese|rolling|acid|stab|pluck|riser|reverse|impact ...)
  genres:      [dnb, liquid, neuro, jungle, house, deep, tech, prog, acid, techno, minimal, dub,
                trance, uplift, psy, ukg, dubstep]
  bpm:         number or range          (clips pitch/stretch within +/-4%; else reject)
  key:         "Fm"|nil                 (nil = key-agnostic: drums, noise, fx, atonal)
  keyAgnostic: bool                     (true for unpitched or one-note sub on tonic)
  bars:        1|2|4|8|16|32            (loop length in bars)
  canLoop:     bool                     (seamless)
  oneShot:     bool                     (impact/crash/riser: use once at boundary)
  energy:      0..1                     (perceived intensity of this clip)
  density:     0..1                     (note/onset density per bar)
  brightness:  0..1                     (spectral centroid; hats/risers high, sub low)
  low:         0..1                     (low-frequency weight; used for exclusion)
  mood:        [dark, tense, soulful, euphoric, warm, eerie, aggressive, dreamy, playful, hypnotic]
  swing:       0..1                     (garage/jungle shuffle)
  halftime:    bool                     (half-time feel)
  intro_safe:  bool                     (no tonal content; DJ-intro/outro eligible)
  slot:        "foundation"|"drive"|"accent"|"texture"|"transition"
  pairsWith:   [role/sub/tag...]        (soft preferences)
  conflictsWith: [role/sub/tag...]      (hard exclusions)
  phraseAnchor: "start"|"end"|"any"     (fills = "end" ; impacts = "start")
}
```

### 3.3 Default pairing and conflict rules

- **Hard conflicts (same bar)**: two `bass` clips with `low>0.5`; `break` + programmed `kick`/`snare` (unless break is layered *only* as tops); `riser` + hypnotic/dub genre; two `chords` at different keys; `rolling` bass + `offbeat` bass; half-time snare + full-time snare; `acid` line + `lead`; big `pad` + dub `chords` (same reverb space); `vocal phrase` + `vocal phrase`.
- **Soft pairs**: kick + hats; reese + distorted fx + noise perc; liquid piano + pad + vocal; acid + 4/4; uplift lead + piano + supersaw chord + snare roll; ukg vocal chop + stab + syncopated bass; psy rolling bass + zap lead + perc tops.
- **Budget rules**: max 1 bass, max 1 lead/vocal-hook, max 2 chord/pad voices, max 3 percussion loops, max 1 fx-transition per phrase boundary. Sum of `density` for non-drums <= ~2.0; sum of `low` <= 1.1. [K]
- **Intro/outro**: only `intro_safe` clips; `drums+perc` and optionally `atmos`; no key.

### 3.4 Slot model (for a generator)

Foundation (kick, base hats, atmos) always on; Drive (bass, snare/clap, perc, break); Accent (stab, lead, vocal, arp); Texture (pad, noise); Transition (fx). Each phrase has an *on-set* for each slot; moves (section 4) change the on-set at phrase boundaries.

---

## 4. Catalogue of arrangement moves

Position notation: phrase of N bars; "bar N" = last bar; "bar 1" = downbeat of next phrase.

| # | Move | Where in phrase | Typical lengths | Genres | Notes |
|---|---|---|---|---|---|
| 1 | **Layer in** one element on the phrase boundary | bar 1 of 8/16/32 phrase | 1 new clip | all | the core move of plateau genres; "each 32-bar block adds or subtracts one element" |
| 2 | **Layer out** one element | bar 1 or after fill | 1 clip | all | outro = repeated layer-out, melodic first |
| 3 | **Filter sweep (HP/LP) on a bus** | spread across last 4-16 bars, resets on bar 1 | 4/8/16/32 | techno, house, trance, DnB | "automate single parameters over 16-32 bars" |
| 4 | **Kick drop-out** | bars 5-8 of an 8-bar or last 8 of 16/32 | 2, 4, 8, 16 bars | techno, house, trance (mini-break at bar 16 of drop, 2-4 bars) | kick comes back on bar 1 with impact/crash |
| 5 | **Bass drop-out / low-cut** | along with 4, or alone | 1-8 bars | all | silence in low end as tool |
| 6 | **Swap bassline** | boundary of 8/16 | replaces | DnB (drop B differs), dubstep, tech house | change `sub`->`reese`, or pattern A->B; never overlap |
| 7 | **Drum fill** | last 1-2 bars of 8/16 (snare roll, tom run, break fill) | 1-2 bars | all | with crash on bar 1 |
| 8 | **Snare roll accelerating** | last 4-8 bars before drop (1/4 -> 1/8 -> 1/16 -> 1/32) | 4-8 | trance, DnB, brostep | add pitch rise |
| 9 | **Riser + reverse cymbal + impact** | riser spans build; reverse cymbal last 1-2 bars; impact bar 1 | 4-16 bars | song-shaped only | "three concurrent layers" for trance; absent in techno/minimal/jungle |
| 10 | **Breakdown without riser** | drop to pad + vocal or single melody, drums removed, resolves with a drum fill | 8-32 | deep house, liquid, progressive, dub | returns on bar 1 |
| 11 | **Drumless breakdown** | all drums out, pads/vocals/sub | 16-32 | DnB, trance, house | final bar: 1-beat silence or snare tail |
| 12 | **Silence/stop (gap)** | last 1/2-2 beats before drop | 0.25-2 bars | dubstep, DnB, trance | strongest cheap tension |
| 13 | **Half-time switch** | at 8/16 boundary or after build | 8-16 | DnB (neuro/darkstep), dubstep, trap-ish | snare moves from 2&4 to beat 3 of the bar; hats can remain full-time |
| 14 | **Double-time / hat densify** | boundary | 8 | techno, DnB, house | add 16th hats or offbeat shaker |
| 15 | **Percussion swap** | every 8 | | techno/house | rotate tom/conga/shaker loop |
| 16 | **Chord/melody change** | 4 or 8 bar harmonic rhythm | | trance, prog, liquid | the loop = 4 chords x 2 bars or 4x4; second half transposed |
| 17 | **Key lift** | final drop | +1/+2 semitones | uplifting trance, pop-edm | whole tonal set shifts |
| 18 | **Mid-drop mini-break** | bar 16 of 32 drop | 2-4 bars | trance, house | remove kick+bass, add noise/hat |
| 19 | **Reverb/delay throw** | last beat of phrase | 1 beat | dub techno, deep house, dnb | dry tail hits last note |
| 20 | **Vocal call** | bars 1-2 or 7-8 of a phrase | 1-2 bars | UKG, jungle, jump-up, house | pre-drop vocal sample in dubstep |
| 21 | **Re-intro (restart)** | after breakdown | 8 | jungle, DnB | break + vocal returns before drop |
| 22 | **Processing morph** | across 16-32 bars | | hypnotic, psy | reverb wet->dry, resonance up |
| 23 | **Micro-edit / stutter** | last 1/2 bar | | minimal, UKG | repeat 1/8 slices |
| 24 | **Second-drop escalation** | the second big section | | song-shaped | +1 layer, new bass, harder drums, or key lift |
| 25 | **Tail out** | last 8-32 bars | | all | strip to drums; end on loop-aligned bar |

Where moves occur: A phrase's position hierarchy: *bar 1* = layer-in, impact, bass swap; *bars 2-4* = settle; *bar 5* = mid-phrase pivot (perc swap, small automation start); *bar 7-8* (of 8) = fill, filter, drop-out; in a 16/32 phrase, bar 9/17 get secondary events and bars N-1..N get fills. Rule: probability of an event at bar position p of phrase: p=1 ~ 0.6, p=N/2+1 ~ 0.3, p=last ~ 0.5 (fill), others <0.1.

---

## 5. Energy-curve model for a 4-5 minute track (no intro/build/drop labels)

### 5.1 Principle

Treat the track as a *long canvas of clips* on lanes (kick, snare, hats, perc, bass, chord, pad, lead, vocal, atmos, fx). Energy `E(bar)` is a continuous curve that is **piecewise-constant over phrases** with a slow trend plus periodic events. Sections are what a human sees when the curve is quantized, not an input. This is how DJ tools are built: one continuous evolution with phrase-aligned changes; the first and last 32-64 bars are mixable (drums only), the middle holds one or two peaks.

### 5.2 Sizing

At 174 BPM, 4:30 = about 195 bars; at 140, 4:30 = 157 bars; at 128, 4:30 = 144 bars. Round to a multiple of 32 (e.g. 192 bars at 174 = 4:25; 160 at 140 = 4:34; 144 or 160 at 128 = 4:30 / 5:00). Treat the length as N phrases of 8: N = 20-26.

### 5.3 The curve

Define E(p) over phrase index p (8-bar phrases), with e in [0,1]. Components:

```
E(p) = base(p) + 0.08 * wave(p mod 4)  + event(p)
base: piecewise linear through anchors (bars -> energy)

  anchors for 192 bars (4:25 @ 174):
     0  : 0.25      DJ intro: kick+hat (+atmos)
    32  : 0.45      +bass or +perc: foundation stage
    64  : 0.65      +lead/stab/chords: first plateau
    96  : 0.85      PEAK A (all lanes except one)         <- first big moment
   112  : 0.55      reduction (kick-out/bass-out 8 bars, pad/vocal only) = "valley"
   128  : 0.90      PEAK B (new bass + extra perc, key lift optional)
   160  : 0.60      stepdown: lose lead, then chords
   192  : 0.25      outro: drums only; end on a downbeat
```
Shape: staircase (plateaus of 16-32 bars, each step 0.1-0.2), one valley of 8-16 bars at 55-70% of the track, a late second peak slightly higher than the first. For loop-evolution genres (techno/minimal/psy) flatten: peak 0.7-0.8, valley depth 0.15, no key lift, change via processing. For song-shaped genres (dnb dancefloor, trance, brostep) deepen valley to 0.3-0.4 (drums out) and add a 4-16 bar rising ramp *immediately before* the peak.

Genre parameter sets (anchors proportions of the 0..1 track length):

| Genre | peak A at | valley at | valley depth | peak B at | riser prob | kick-out | outro tail |
|---|---|---|---|---|---|---|---|
| DnB dancefloor/neuro | 20-25% | 50-55% | 0.3-0.4 (drumless) | 60-65% | 0.9 | n/a (drums out whole) | 12-16% |
| DnB liquid | 20% | 45-55%, long (16-32 bars) | 0.3 | 60% | 0.4 | | 12% |
| Jungle | 30% | 55% | 0.2 (break thinned) | 65% | 0.1 | | 15% |
| Techno minimal/hypnotic | 50% | 40% (kick-out) | 0.1 | none or 70% | 0 | 8 bars | 20% |
| Techno peak-time | 45% | 55% | 0.2 | 70% | 0.3 | 8-16 bars | 18% |
| Deep house | 35% | 25% and 60% (several 8-16 bar breaks) | 0.25 | 80% | 0.1 | 8 bars | 10-15% |
| Tech house | 25% (after beatless break) | 35% | 0.3 | 60% | 0.4 | last bar of kick | 12% |
| Progressive house/trance | 30% | 50% (breakdown 20-30% of track) | 0.4 | 70% | 0.9 (trance) / 0.5 | mini-break | 15% |
| Psytrance | 30% | 55% (short) | 0.15 | 70% | 0.1 | 4 bars | 15% |
| UKG | 20% | 45% | 0.3 (vocal+pad) | 65% | 0.1 | | 10% |
| Dubstep deep | 25% | 50% | 0.25 | 70% | 0.3 | | 15% |
| Brostep | 20% | 45% | 0.2 | 65% | 0.9 | silence 1-2 bars | 15% |

### 5.4 Per-phrase event generation (phrase-aligned)

For each 8-bar phrase p:
1. Compute target energy `E(p)` from the curve; map to a target number of active lanes `n = round(2 + 7*E)` and target density.
2. At bar 1 of each *16-bar* boundary, allow +1/-1 lane change in the direction of dE; at bar 1 of each *32-bar* boundary allow +/-2 and a bass swap.
3. Pick the lane to add by a fixed preference order, chosen from the genre's layer map: kick -> hats -> (bass | perc) -> clap/snare -> chords/stab -> arp -> lead/vocal -> fx. Pick the lane to remove in reverse order but *keep kick last*.
4. In the last 1-2 bars before any phrase with |dE| >= 0.15: place a fill (+ riser/reverse cymbal if genre `riserProb`); on bar 1: impact/crash.
5. When E drops by >= 0.25 between phrases: remove kick/bass (or entire drums) for that phrase, keep pad/atmos/vocal; the return phrase gets the impact and the biggest add.
6. Every phrase: one 8-bar *processing automation* lane (filter/reverb) ramps 0->1 over bars 1-8 or 1-16, resets on boundary.
7. Mutually exclusive checks per section 3.3 before accepting each addition; if conflict, *swap* the clip instead of stacking.
8. Harmony: choose a 4-chord loop at bar 1 of each 16-bar phrase; keep or rotate on 16-bar boundaries; bass follows chord roots (or a single tonic for techno/neuro). Key lift only at peak B if genre allows.
9. Intro/outro: p in first 2-4 phrases and last 2-4 phrases restricted to `intro_safe` clips; outro mirrors intro layer order reversed.

### 5.5 Worked skeleton: 4:25 DnB (174, 192 bars, bars numbered from 1)

```
 1-16   kick+snare(2-step), hats                 E .25  (DJ intro)
17-32   + tops loop, + atmos pad                 E .35  (fill at bar 32)
33-48   + sub bass (sparse)                      E .50
49-64   + stab/chord, + percussion               E .65  (riser/filter-open 61-64, impact at 65)
65-96   FULL: reese+sub, drums, lead A           E .85  (bass swap at 81; fill at 80, 96)
97-112  breakdown: pad + vocal, drums out        E .40  (reverse cymbal 111-112, no riser)
113-128 half-time drop (bass B, new perc)        E .90  (hat densify at 121)
129-160 FULL, lead B/counter-melody, 2 vocal chops  E .90
161-176 reduce: lose lead -> lose chord           E .60
177-192 drums+hat only, pad tail                 E .25  (mix-out)
```
Equivalent 4:30 deep-techno at 128 BPM (144 bars): 1-32 kick/hat/perc loop; 33-64 + sub-rumble; 65-80 + stab with delay; 81-96 + percussion 2; 97-104 kick out (bass and stab stay, hats filtered); 105-128 everything + 1 extra perc; 129-144 strip melodic first, then bass, end drums. No riser anywhere; filter and delay-feedback automation over 16-bar spans.

### 5.6 Implementation notes

- Quantize all clip starts/stops to 8 bars (4 only for fills/stabs inside a phrase). Never introduce a tonal clip off a phrase boundary.
- Keep a `state` per lane (`on`, `clipId`, `since`) and make the generator a *difference* process: each phrase emits only the delta from the previous.
- Make the same seed produce the same curve; vary anchors by +/-4 bars of multiples of 8.
- Provide the preview as a lane x bar grid with the E curve on top; the visual should read as a continuous map, not labelled sections.
- Genre switches change: tempo, riserProb, valley depth, bass types, drum-pattern family, harmony set, intro length (16/32/64), allowed lanes.

---

## Sources

- https://kansamples.com/blogs/learn/dnb-track-arrangement (DnB template, 32/16/64/32 bars, build elements)
- https://kansamples.com/blogs/learn/dubstep-track-arrangement (dubstep 140: halftime, 32-bar drops, mistakes)
- https://www.edmprod.com/how-to-make-drum-and-bass/ (DnB subgenres, tempo, keys, bass range)
- https://www.edmprod.com/how-to-make-liquid-drum-and-bass/ (liquid: 174, F minor, 16-bar sections, two-step)
- https://www.edmprod.com/how-to-make-dubstep/ (UK 140, deep vs brostep, 8-bar increments)
- https://www.edmprod.com/how-to-make-techno/ (techno subgenres, tempo, 16-32 bar sections)
- https://www.edmprod.com/how-to-make-tech-house/ (125-128, structure, keys)
- https://tracksensei.com/blog/how-to-arrange-a-techno-track (techno 32-bar plateau map)
- https://thevelvetshadow.com/electronic-music-structure (8-bar loop expansion, change every 8-16)
- https://www.myloops.net/analyzing-the-arrangement-of-a-professional-trance-track (trance bar-by-bar)
- https://www.myloops.net/how-to-arrange-an-uplifting-trance-track-from-start-to-finish (uplifting 8-minute blueprint)
- https://www.myloops.net/ultimate-guide-to-progressive-house-track-structure-and-flow (prog house bars, chords)
- https://mixedinkey.com/captain-plugins/wiki/how-to-arrange-a-dance-music-track/ (deep house, DnB, 140 real-track maps)
- https://www.loopmasters.com/articles/4564-How-To-Make-A-Neurofunk-Drum-and-Bass-Breakdown (neuro breakdown layering, filename tagging)
- https://www.beatportal.com/articles/818379-step-by-step-guide-to-producing-drum-and-bass-like-sub-focus-a-m-c-and-delta-heavy (DnB bass layers, timeline)
- https://musicproductionwiki.com/articles/how-to-make-jungle-music (jungle tempo, break, bass, template)
- https://www.musicradar.com/how-to/uk-garage-tutorial (UKG 2-step, swing, vocals)
- https://blog.native-instruments.com/tech-house/ and https://blog.native-instruments.com/drum-and-bass/ (search-result summaries only)
- https://splice.com/sounds/tags/dark/samples (Splice tag/metadata model: genre, instrument, key, BPM, mood tags)
- https://vibesdj.io/dj-tools/what-bpm-is-psytrance and https://vibesdj.io/dj-tools/what-bpm-is-jungle (BPM ranges; search-result summaries)
- https://www.myloops.net/ (psytrance 145 BPM, rolling bass, sidechain release; search-result summary)
- https://en.wikipedia.org/wiki/2-step_garage, https://en.wikipedia.org/wiki/Breakstep, https://en.wikipedia.org/wiki/Future_garage (genre background; search-result summaries)
- https://www.dogsonacid.com/threads/dnb-structure.765121/ (returned 403; not read)

Caveats: several fetches were summarized by a small model; numbers marked [K] (dub techno, minimal, future garage, deep-house tempo, psy bass note set, move probabilities, energy anchors, slot budgets) are domain-knowledge defaults, not source-verified, and the energy-curve numbers are a proposed model, not measured data.
