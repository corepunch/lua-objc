_G.__headless = true
-- The authored library and the engines that play it: the notation beats,
-- lines and hooks are written in, patches and their loudness, drum loops
-- and their slices, and what the generator writes itself.
local t = require("TestKit")
local Library = require("apps.dnb.host.Library")
local Motif = require("apps.dnb.host.Motif")
local StyleKit = require("apps.dnb.host.StyleKit")
local Styles = require("apps.dnb.host.Styles")
local Drums = require("apps.dnb.models.Drums")
local Instrument = require("apps.dnb.models.Instrument")
local Calibration = require("apps.dnb.models.Calibration")
local Model = require("apps.dnb.Model")

local SR = 11025

-- Notation: beats.
local beat = Library.beat({id = "test.beat", bars = 2, lanes = {
	{"kick", "X.........x.....|X.....x...x....."},
	{"snare", "....X.......X..."},
	{"hat", "x.x.x.x.x.x.x.x.", gain = 0.5, when = "energy"},
	{"ghost", ".......g........", when = "complexity", light = false},
	{"snare", "........................ggooxxXX", div = 32, when = "complexity"},
}})
t.assertEqual(beat.slices, 32, "a two-bar beat is 32 slices")
local function count(voice, when)
	local n = 0
	for _, hit in ipairs(beat.hits) do
		if hit.voice == voice and hit.when == when then n = n + 1 end
	end
	return n
end
t.assertEqual(count("kick"), 5, "a lane as long as the beat is played once")
t.assertEqual(count("hat", "energy"), 16, "a shorter lane repeats to fill it")
for _, hit in ipairs(beat.hits) do
	if hit.voice == "kick" and hit.step == 0 then t.assertEqual(hit.gain, 1, "an accent plays at full level") end
	if hit.voice == "kick" and hit.step == 10 then t.assertEqual(hit.gain, 0.8, "a plain hit a little under it") end
	if hit.voice == "hat" then t.assertEqual(hit.gain, 0.4, "a lane's gain scales its hits") end
end
local fractional = false
for _, hit in ipairs(beat.hits) do
	if hit.step % 1 ~= 0 then fractional = true end
	t.expect(hit.step >= 0 and hit.step < 32, "hits stay inside the beat")
end
t.expect(fractional, "a lane in 32nds lands between the 16ths")
t.assertEqual(table.concat(beat.snareSlices, " "), "4 12 20 28", "full snares on the grid are known slices")
for i = 2, #beat.hits do t.expect(beat.hits[i].step >= beat.hits[i - 1].step, "hits are in step order") end
t.assertThrows(function() Library.beat({id = "x", lanes = {{"cowbells", "x..."}}}) end, "a beat plays kit voices only")
t.assertThrows(function() Library.beat({id = "x", lanes = {{"kick", "x.."}}}) end, "a lane is written in whole bars")
t.assertThrows(function() Library.beat({id = "x", lanes = {{"kick", "x..?x..........."}}}) end, "unknown steps are refused")
t.assertThrows(function() Library.beat({id = "x", kit = "break", lanes = {{"kick", "x..............."}}}) end,
	"a record's break needs its tempo")
local kicks, snares = Library.accents(beat, 0, 16, "full", true, true)
t.assertEqual(table.concat(kicks, " ") .. " / " .. table.concat(snares, " "), "0 10 / 4 12 14 14.5 15 15.5",
	"a bar's accents are its kicks and full snares")
t.assertEqual(#select(2, Library.accents(beat, 0, 16, "full", true, false)), 2, "of the layers that play")
t.assertEqual(#Library.accents(beat, 0, 16, "tops", true, true), 0, "the tops carry no kick")
t.expect(Drums.plays({voice = "hat", when = "energy"}, "full", true, false), "energy lets its layers in")
t.expect(not Drums.plays({voice = "hat", when = "energy"}, "full", false, true), "and keeps them out while it is down")
t.expect(not Drums.plays({voice = "hat", when = "energy"}, "light", true, true), "the light variant has no extra layers")
t.expect(not Drums.plays({voice = "ghost", light = false}, "light", true, true), "nor what a beat keeps out of it")
t.expect(Drums.plays({voice = "kick"}, "light", false, false), "but its kick")

-- Notation: lines and hooks.
local line = Library.notes("0:0:6 8:7:2~ 12:4:3! | 0:0:8 10:2b:2? 14:-1:1.5+w3")
t.assertEqual(line.bars, 2, "bars are split by a bar line")
t.assertEqual(#line.notes, 6, "every note is read")
t.assertEqual(line.notes[2].offset .. " " .. tostring(line.notes[2].glide), "7 true", "a tilde slides into its note")
t.expect(line.notes[3].accent, "an exclamation mark accents")
t.assertEqual(line.notes[5].step .. " " .. line.notes[5].bend, "26 -1", "a flat bends a semitone, in the second bar")
t.expect(line.notes[5].chance > 0.5 and line.notes[5].detail == 0, "a question mark waits for energy")
t.assertEqual(line.notes[6].offset .. " " .. line.notes[6].rate .. " " .. line.notes[6].length, "-1 3 1.5",
	"offsets may be negative, lengths fractional and a wobble has a rate")
t.expect(line.notes[6].detail > 0.5, "a plus waits for complexity")
t.assertThrows(function() Library.notes("0:0") end, "a note needs its step, pitch and length")
t.assertThrows(function() Library.notes("16:0:1") end, "a note starts inside its bar")
t.assertThrows(function() Library.notes("0:0:1%") end, "unknown flags are refused")
local steps, accents = Library.steps("X..x..x.")
t.assertEqual(table.concat(steps, " "), "0 3 6", "a rhythm is its onsets")
t.expect(accents[0] and not accents[3], "with its accents")

-- The shared library: everything parses, and ids are unique.
local shared = Library.shared()
local counts = {}
for _, kind in ipairs(Library.kinds) do
	counts[kind] = 0
	for id, entry in pairs(shared[kind]) do
		counts[kind] = counts[kind] + 1
		t.assertEqual(entry.id, id, kind .. " are looked up by id")
	end
end
t.expect(counts.patches >= 60, "the library holds " .. counts.patches .. " patches")
t.expect(counts.hooks >= 24, "and " .. counts.hooks .. " hooks")
t.expect(counts.beats >= 15, "and " .. counts.beats .. " breaks and fills")
t.assertThrows(function() shared:get("patches", "bass.kazoo") end, "an unknown patch is an error")
t.assertEqual(shared:get("beats", "break.amen").bars, 4, "the Amen is four bars")
t.assertEqual(shared:get("beats", "break.amen").bpm, 137, "at the record's tempo")
t.expect(#shared:get("beats", "break.amen").snareSlices >= 6, "its snares are known slices")
for id, hook in pairs(shared.hooks) do
	t.assertEqual(hook.bars, 4, id .. " is four bars")
	local last = hook.notes[#hook.notes]
	t.expect(last.bar == 3, id .. " plays to its last bar")
	for _, note in ipairs(hook.notes) do
		t.expect(note.offset >= -3 and note.offset <= 11, id .. " stays within an octave and a half")
		t.expect(note.step % 16 + note.length <= 16, id .. " notes end inside their bar")
	end
	-- Notes of one hook never overlap: a lead is one voice.
	for i = 2, #hook.notes do
		t.expect(hook.notes[i].step >= hook.notes[i - 1].step + hook.notes[i - 1].length - 1e-9,
			id .. " is one voice, note " .. i)
	end
end
-- A style's library lies over the shared one.
for _, style in ipairs(Styles:list()) do
	local library = Library.of(style)
	local own = 0
	for id in pairs(library.beats) do if not shared.beats[id] then own = own + 1 end end
	t.expect(own >= 5, style.title .. " brings " .. own .. " grooves of its own")
	t.expect(library.patches["bass.sub"] ~= nil, style.title .. " plays the shared patches")
	for id, entry in pairs(library.lines) do
		for _, note in ipairs(entry.notes) do
			t.expect(note.step % 16 + note.length <= 16.6, style.title .. " line " .. id .. " keeps its notes in the bar")
		end
	end
end

-- Patches: checked, and levelled to their role.
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "kazoo"}}}) end, "unknown waves are refused")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw"}}, wub = 1}) end, "unknown fields are refused")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw", fm = {ratio = 2}}}}) end, "only a sine takes FM")
t.assertThrows(function() Instrument.patch({id = "x", osc = {{wave = "saw"}}, filter = {kind = "comb"}}) end,
	"unknown filters are refused")
t.assertThrows(function() Instrument.patch({id = "x"}) end, "a patch needs an oscillator")
local plain = Instrument.patch({id = "x", osc = {{wave = "saw", octave = 1, detune = 0.01}}})
t.expect(math.abs(plain.osc[1].ratio - 2.02) < 1e-9, "an oscillator's ratio is its octave and detune")
t.assertEqual(plain.amp.sustain .. " " .. tostring(plain.mono) .. " " .. plain.level, "1 false 1", "what a patch leaves out is filled in")
local byRole = {}
for id, patch in pairs(shared.patches) do
	t.expect(Model.family[patch.role] ~= nil, id .. " names a real role")
	t.expect(patch.name ~= id and #patch.name <= 14, id .. " has a name that fits a channel: " .. patch.name)
	byRole[patch.role] = (byRole[patch.role] or 0) + 1
	local offset = Calibration.offset(patch)
	t.expect(math.abs(offset) <= Calibration.tolerance, string.format("%s sits %+.1f dB from its role's level", id, offset))
end
for _, role in ipairs({"bass", "pad", "keys", "stab", "arp", "lead"}) do
	t.expect(byRole[role] >= 7, "there are " .. tostring(byRole[role]) .. " patches for the " .. role)
end

-- The instrument: voices sound, end, and differ by patch.
local function play(patch, notes, seconds, options)
	options = options or {}
	local frames = math.floor(seconds * SR)
	local out = {left = {}, right = {}, throwL = {}, throwR = {}}
	for k = 1, frames do out.left[k], out.right[k], out.throwL[k], out.throwR[k] = 0, 0, 0, 0 end
	local voice = Instrument.voice(patch, notes, {sr = SR, hold = math.floor((options.hold or 0.2) * SR), gain = 1, seed = 3,
		throw = options.throw, accent = options.accent})
	local ctx = {tempo = 120, scratchL = {}, scratchR = {}, shift = options.shift or 0, wobble = 1, drive = 1}
	local done
	local size = options.block or frames
	for first = 1, frames, size do
		done = Instrument.render(voice, first, math.min(frames, first + size - 1), out, ctx)
	end
	return out, done, voice
end
local function level(data, from, to)
	local sum = 0
	for k = from, to do sum = sum + data[k] * data[k] end
	return math.sqrt(sum / (to - from + 1))
end
-- Brightness: how much of a signal changes from one frame to the next.
local function rough(data, from, to)
	local sum = 0
	for k = from + 1, to do sum = sum + (data[k] - data[k - 1]) ^ 2 end
	return math.sqrt(sum / (to - from)) / math.max(level(data, from, to), 1e-12)
end
for id, patch in pairs(shared.patches) do
	local out, _, voice = play(patch, patch.role == "bass" and {36} or {60, 64, 67}, 0.4)
	local peak = 0
	for k = 1, #out.left do
		local a = math.abs(out.left[k])
		if a ~= a then peak = math.huge break end
		peak = math.max(peak, a)
	end
	t.expect(peak > 1e-4 and peak < 4, id .. " sounds, and stays bounded")
	t.expect(voice.tick == #out.left, id .. " renders every frame")
end
local pluck = shared:get("patches", "pluck.saw")
local out, done = play(pluck, {72}, 2, {hold = 0.1})
t.expect(done, "a plucked voice ends")
t.expect(level(out.left, 1, SR // 10) > 20 * level(out.left, SR, 2 * SR), "having died away")
local _, held = play(shared:get("patches", "pad.saw"), {60}, 0.5, {hold = 1})
t.expect(not held, "a held voice plays on")
local whole = play(shared:get("patches", "bass.reese"), {36}, 0.5, {hold = 0.3})
local chunks = play(shared:get("patches", "bass.reese"), {36}, 0.5, {hold = 0.3, block = 97})
local same = true
for k = 1, #whole.left do if whole.left[k] ~= chunks.left[k] then same = false break end end
t.expect(same, "a voice renders the same in blocks of any size")
local dark = play(shared:get("patches", "bass.reese"), {36}, 0.4, {hold = 0.4, shift = -2})
local bright = play(shared:get("patches", "bass.reese"), {36}, 0.4, {hold = 0.4, shift = 2})
t.expect(rough(bright.left, 1000, 4000) > 1.5 * rough(dark.left, 1000, 4000), "the Filter slider opens the bass")
local soft = play(shared:get("patches", "bass.acid"), {48}, 0.2, {hold = 0.2})
local accented = play(shared:get("patches", "bass.acid"), {48}, 0.2, {hold = 0.2, accent = true})
t.expect(level(accented.left, 1, 2000) > level(soft.left, 1, 2000), "an accent plays harder")
local thrown = play(pluck, {72}, 0.2, {throw = 1})
t.expect(level(thrown.throwL, 1, 1000) > 0 and level(out.throwL, 1, 1000) == 0, "a thrown voice feeds the delay")
local wide = play(shared:get("patches", "pad.supersaw"), {60, 64}, 0.6, {hold = 0.6})
local differs = false
for k = 3000, 6000 do if math.abs(wide.left[k] - wide.right[k]) > 1e-6 then differs = true break end end
t.expect(differs, "a wide patch differs from side to side")
local narrow = play(shared:get("patches", "bass.sub"), {36}, 0.2)
t.assertEqual(narrow.left[500], narrow.right[500], "a bass sits in the middle")
-- Timbre is what tells two tracks apart: patches of one role are not
-- copies of each other.
for _, role in ipairs({"bass", "pad", "lead", "arp"}) do
	local seen, distinct = {}, 0
	for id, patch in pairs(shared.patches) do
		if patch.role == role then
			local sound = play(patch, role == "bass" and {36} or {60}, 0.4, {hold = 0.4})
			local key = string.format("%.2f", math.log(rough(sound.left, 500, 4000) + 1e-9))
			if not seen[key] then seen[key], distinct = true, distinct + 1 end
		end
	end
	t.expect(distinct >= byRole[role] * 0.6, role .. " patches differ in brightness: " .. distinct .. " of " .. byRole[role])
end
-- A mono voice glides to a tied note and starts again on a struck one.
local lead = shared:get("patches", "lead.sine")
local mono = Instrument.voice(lead, {60}, {sr = SR, hold = 2000, gain = 1})
local sink = {left = {}, right = {}, throwL = {}, throwR = {}}
for k = 1, 6000 do sink.left[k], sink.right[k], sink.throwL[k], sink.throwR[k] = 0, 0, 0, 0 end
local ctx = {tempo = 120, scratchL = {}, scratchR = {}}
Instrument.render(mono, 1, 1000, sink, ctx)
Instrument.retarget(mono, 67, {hold = 2000, gain = 1, glide = true})
t.expect(mono.freq < mono.target, "a tied note starts from the pitch before it")
Instrument.render(mono, 1001, 1200, sink, ctx)
t.expect(mono.freq > Instrument.midiHz(60) and mono.freq < mono.target, "and slides towards its own")
Instrument.retarget(mono, 72, {hold = 2000, gain = 1})
t.assertEqual(mono.freq, mono.target, "a struck note starts on its pitch")
t.expect(Instrument.sounding(mono), "and the voice plays on")

-- Drums: kits, and loops rendered from beats.
local kit = Drums.design()
local shots = Drums.shots(SR, kit)
t.expect(#shots.kick > 0 and #shots.crash > 0 and #shots.cowbell > 0, "a kit has its own voices and the shared ones")
t.expect(Drums.shots(SR, kit) == shots, "kits are cached by design")
t.assertThrows(function() Drums.design({kick = {wub = 1}}) end, "unknown kit fields are refused")
t.assertThrows(function() Drums.design({gong = {}}) end, "unknown kit groups are refused")
for voice in pairs(Drums.place) do t.expect(shots[voice] ~= nil and #shots[voice] > 0, voice .. " is rendered") end
local tail = SR // 20
local ride = shots.ride
t.expect(level(ride, #ride - tail, #ride) < level(ride, 1, tail) * 0.05, "the ride's tail decays below 5% of its attack")
local options = {tempo = 170, swing = 0, humanize = 0, variant = "full", energy = true, complexity = true}
local loop = Drums.loop(SR, shots, beat, options)
t.assertEqual(loop.slices, 32, "a loop has its beat's slices")
t.assertEqual(loop.frames, math.floor(32 * SR * 60 / 170 / 4 + 0.5), "rendered at the track's tempo")
t.expect(math.abs(loop.step - SR * 60 / 170 / 4) < 1e-9, "a slice is a 16th")
t.expect(Drums.loop(SR, shots, beat, options) == loop, "loops are cached")
local function slice(data, index) return level(data, math.floor(index * loop.step) + 1, math.floor((index + 1) * loop.step)) end
t.expect(slice(loop.left, 0) > 4 * slice(loop.left, 5), "the kick's slice is louder than the one after the snare's tail")
t.expect(slice(loop.left, 4) > 0.05, "the snare sounds on the backbeat")
t.expect(loop.left ~= loop.right, "a programmed loop is stereo")
local light = Drums.loop(SR, shots, beat, {tempo = 170, variant = "light"})
t.expect(level(light.left, 1, light.frames) < level(loop.left, 1, loop.frames), "the light variant plays less")
local tops = Drums.loop(SR, shots, beat, {tempo = 170, variant = "tops", energy = true})
t.expect(slice(tops.left, 0) < slice(loop.left, 0) * 0.5, "the tops leave the kick out")
local quiet = Drums.loop(SR, shots, beat, {tempo = 170, variant = "full"})
t.expect(quiet ~= loop and level(quiet.left, 1, quiet.frames) < level(loop.left, 1, loop.frames), "energy adds its layers")
local swung = Drums.loop(SR, shots, beat, {tempo = 170, swing = 0.3, variant = "full", energy = true})
local moved = false
for k = 1, loop.frames do if swung.left[k] ~= loop.left[k] then moved = true break end end
t.expect(moved, "swing is part of the loop")
local amen = Drums.loop(SR, shots, shared:get("beats", "break.amen"), {tempo = 170})
t.assertEqual(amen.frames, math.floor(64 * SR * 60 / 137 / 4 + 0.5), "a record's break is rendered at the record's tempo")
t.assertEqual(amen.tempo, 137, "and says so, to be sped up")
t.expect(amen.left == amen.right, "in mono")
local peak = 0
for k = 1, amen.frames do peak = math.max(peak, math.abs(amen.left[k])) end
t.expect(peak > 0.2 and peak <= 1.5, "at a level a channel can play")
local other = Drums.shots(SR, kit, {snare = "fat", snareTune = -1, kickTune = 1, kickLength = 0, kickDrive = 0,
	kickClick = 0, hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0})
t.expect(Drums.loop(SR, other, beat, options) ~= loop, "another kit plays another loop")

-- Loops a track will need are prepared a little at a time, and play the
-- same as loops rendered at once.
local ahead = {snare = "roomy", snareTune = 0.5, kickTune = -0.5, kickLength = 0.2, kickDrive = 0, kickClick = 0,
	hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0}
local wanted = {tempo = 172, swing = 0.1, humanize = 0.3, variant = "full", energy = true}
Drums.prepare(SR, kit, ahead, beat, wanted)
local steps_ = 0
while Drums.work(0) do steps_ = steps_ + 1 end
t.expect(steps_ > 10, "a loop is prepared in many small steps: " .. steps_)
t.expect(not Drums.work(0), "until nothing is left to do")
local clock = os.clock()
local prepared = Drums.loop(SR, Drums.shots(SR, kit, ahead), beat, wanted)
t.expect(os.clock() - clock < 0.005, "and is ready when its bar comes")
local later = {snare = "fat", snareTune = 0.5, kickTune = -0.5, kickLength = 0.2, kickDrive = 0, kickClick = 0,
	hatTone = 0, hatLength = 0, hatNoise = 0, clapSpread = 0, clapLength = 0, clapTone = 0}
Drums.prepare(SR, kit, later, beat, wanted)
Drums.work(0)
local hurried = Drums.loop(SR, Drums.shots(SR, kit, later), beat, wanted)
t.assertEqual(hurried.frames, prepared.frames, "a loop wanted before it is ready is finished at once")
t.expect(not Drums.work(0), "leaving nothing behind")
local direct = Drums.loop(SR, Drums.shots(SR, kit, later), beat, {tempo = 172, swing = 0.1, humanize = 0.3, variant = "full",
	energy = true})
t.expect(direct == hurried, "and is the loop any caller gets")
Drums.prepare(SR, kit, later, beat, wanted)
t.expect(not Drums.work(0), "a loop that is ready needs no preparing")

-- Motifs: one idea, developed.
local rng = StyleKit.random(5, 1)
local cell = Motif.cell(rng)
t.expect(#cell.steps >= 3, "a cell has a rhythm")
local motif = Motif.write(rng, cell)
t.assertEqual(#motif, #cell.steps, "a motif has a note on each of its cell's accents")
for i, note in ipairs(motif) do
	t.assertEqual(note.step, cell.steps[i], "in the cell's rhythm")
	t.expect(note.offset >= -2 and note.offset <= 9, "within its range")
	t.expect(note.step + note.length <= 16, "inside the bar")
	if note.step % 4 == 0 then t.expect(note.offset % 7 % 2 == 0 and note.offset % 7 <= 4, "strong beats land on chord tones") end
end
t.assertEqual(Motif.chordTone(1), 0, "the chord tone nearest the second is the root")
t.assertEqual(Motif.chordTone(5), 4, "and nearest the sixth, the fifth")
for _, form in ipairs(Motif.forms) do
	local hook = Motif.develop(StyleKit.random(5, 2), motif, form)
	t.assertEqual(hook.bars, 4, "a hook is four bars")
	local perBar = {0, 0, 0, 0}
	for _, note in ipairs(hook.notes) do
		perBar[note.bar + 1] = perBar[note.bar + 1] + 1
		t.assertEqual(note.step // 16, note.bar, "a note lies in its bar")
		t.expect(note.step % 16 + note.length <= 16, "and ends inside it")
	end
	for bar = 1, 4 do t.expect(perBar[bar] > 0, "every bar of " .. table.concat(form, " ") .. " plays") end
	if form[1] == "a" and form[3] == "a" then
		local first, third = {}, {}
		for _, note in ipairs(hook.notes) do
			if note.bar == 0 then table.insert(first, note.step % 16 .. ":" .. note.offset) end
			if note.bar == 2 then table.insert(third, note.step % 16 .. ":" .. note.offset) end
		end
		t.assertEqual(table.concat(third, " "), table.concat(first, " "), "the motif returns as it was")
	end
	if form[4] == "e" then
		local last = hook.notes[#hook.notes]
		t.assertEqual(last.offset .. " " .. last.length, "0 8", "the ending comes home on a long note")
	end
end
local hook = Motif.develop(StyleKit.random(5, 2), motif)
for _, kind in ipairs(Motif.variations) do
	local varied = Motif.vary(StyleKit.random(5, 3), hook, kind)
	t.assertEqual(varied.bars, hook.bars, kind .. " keeps the hook's length")
	local steps = {}
	for _, note in ipairs(varied.notes) do steps[note.step] = true end
	for _, note in ipairs(hook.notes) do t.expect(steps[note.step], kind .. " keeps the hook's rhythm") end
end
t.assertEqual(Motif.vary(rng, hook, "octave").notes[1].offset, hook.notes[1].offset + 7, "an octave up is seven scale steps")
t.expect(#Motif.vary(rng, shared:get("hooks", "hook.riff"), "busy").notes > #shared:get("hooks", "hook.riff").notes,
	"a busy variation fills the leaps in")
local answer = Motif.answer(rng, hook)
for _, note in ipairs(answer.notes) do t.assertEqual(note.bar % 2, 1, "an answer waits for the hook to finish") end
for name, write in pairs(Motif.lines) do
	for seed = 1, 4 do
		local written = write(StyleKit.random(seed, 9), cell, {rates = {1, 2}})
		t.expect(written.bars >= 1 and #written.notes > 0, name .. " writes a line")
		local always = 0
		for _, note in ipairs(written.notes) do always = always + (note.chance == 0 and 1 or 0) end
		t.expect(always > 0, name .. " has notes that play at any Energy")
		for _, note in ipairs(written.notes) do
			t.expect(note.step >= 0 and note.step < written.bars * 16, name .. " notes lie in the line")
			t.expect(note.step % 16 + note.length <= 16.6, name .. " notes end in their bar")
			t.expect(note.offset >= -7 and note.offset <= 14, name .. " stays near its root")
		end
	end
end
local arp = Motif.arp(rng, {rates = {2}, contour = false})
t.assertEqual(arp.rate, 2, "an arpeggio takes its channel's rate")
t.assertEqual(arp.mask[0] + arp.mask[4] + arp.mask[8] + arp.mask[12], 0, "and always sounds the beats")
local comp = Motif.comp(rng, cell)
t.assertEqual(comp[1].threshold, 0, "the first chord of a comp always sounds")
for _, step in ipairs(Motif.offbeats(cell, 2)) do
	for _, taken in ipairs(cell.steps) do t.expect(step ~= taken, "off-beats are where the cell rests") end
end

-- Theory: a line in scale steps stays in its key.
local minor = StyleKit.modes.minor
t.assertEqual(StyleKit.pitch(minor, 0, 1, 0, 28), 36, "the root folds into its register")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 7, 28), 48, "seven steps up is an octave")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 2, 28), 39, "two steps up a minor third")
t.assertEqual(StyleKit.pitch(StyleKit.modes.major, 0, 1, 2, 28), 40, "or a major one, in a major key")
t.assertEqual(StyleKit.pitch(minor, 0, 1, -1, 28), 34, "a step below the root is the seventh")
t.assertEqual(StyleKit.pitch(minor, 0, 1, 1, 28, -1), 37, "a flat bends a semitone")
for degree = 1, 7 do
	for offset = -3, 9 do
		local pitch = StyleKit.pitch(minor, 2, degree, offset, 64)
		local inKey = false
		for _, step in ipairs(minor.steps) do inKey = inKey or (pitch - 2) % 12 == step end
		t.expect(inKey, "degree " .. degree .. " offset " .. offset .. " is in the key")
	end
end

os.exit(t.summary() and 0 or 1)
