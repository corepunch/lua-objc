-- How loud a patch plays, measured the way it will be heard: a phrase its
-- role would play, rendered and averaged. Patches of one role are levelled
-- to one target, so that a track may take any of them without upsetting
-- the mix. The targets are the balance the generator was first mixed to by
-- ear (a bass near full level, chords and melody some 25 dB under it); a
-- style moves a role from there in its `mix`.
local Instrument = require("apps.dnb.models.Instrument")

local Calibration = {}

Calibration.sampleRate = 22050
Calibration.tempo = 174
-- RMS of a role's phrase on its channel, before the fader.
Calibration.targets = {bass = 0.48, pad = 0.022, keys = 0.021, stab = 0.03, arp = 0.0089, lead = 0.02,
	counter = 0.015, texture = 0.011, fx = 0.035}
-- Decibels a patch may sit from its role's target.
Calibration.tolerance = 1.5

local CHORD = {57, 60, 64, 67}
-- Two bars of what each role plays: {step, length, notes}.
local PHRASES = {
	bass = {{0, 16, {33}}, {16, 16, {33}}},
	pad = {{0, 32, CHORD}},
	texture = {{0, 32, {48, 55}}},
	keys = {}, stab = {}, arp = {}, lead = {},
	fx = {{0, 16, {60}, from = 0.5, to = 1}, {16, 16, {60}, from = 0.5, to = 1}},
}
for bar = 0, 1 do
	for _, step in ipairs({0, 6, 10}) do table.insert(PHRASES.keys, {bar * 16 + step, 2, CHORD}) end
	for _, step in ipairs({3, 6, 11}) do table.insert(PHRASES.stab, {bar * 16 + step, 1, CHORD}) end
	for i = 0, 7 do table.insert(PHRASES.arp, {bar * 16 + i * 2, 1.6, {({72, 76, 79, 84})[i % 4 + 1]}}) end
	for i = 0, 3 do table.insert(PHRASES.lead, {bar * 16 + i * 4, 4, {({76, 79, 81, 79})[i + 1]}}) end
end
PHRASES.counter = PHRASES.lead

--- The RMS of `patch` playing `role`'s phrase (its own role's by default)
--- at its own level.
function Calibration.measure(patch, role)
	role = role or patch.role
	local phrase = assert(PHRASES[role], "no phrase for role " .. tostring(role))
	local sr = Calibration.sampleRate
	local step = sr * 60 / Calibration.tempo / 4
	local frames = math.floor(32 * step + 0.5)
	local out = {left = {}, right = {}, throwL = {}, throwR = {}}
	for k = 1, frames do out.left[k], out.right[k], out.throwL[k], out.throwR[k] = 0, 0, 0, 0 end
	local ctx = {tempo = Calibration.tempo, scratchL = {}, scratchR = {}, shift = 0, wobble = 1, drive = 1}
	local voices, mono = {}, nil
	local events = {}
	for _, note in ipairs(phrase) do
		table.insert(events, {frame = math.floor(note[1] * step + 0.5), note = note})
	end
	local cursor = 0
	local function render(to)
		if to <= cursor then return end
		for i = #voices, 1, -1 do
			if Instrument.render(voices[i], cursor + 1, to, out, ctx) then table.remove(voices, i) end
		end
		if mono and Instrument.sounding(mono) then Instrument.render(mono, cursor + 1, to, out, ctx) end
		cursor = to
	end
	for _, event in ipairs(events) do
		render(event.frame)
		local note = event.note
		local options = {sr = sr, hold = math.floor(note[2] * step * 0.9), gain = 1, seed = event.frame,
			from = note.from, to = note.to}
		if patch.mono then
			if mono then Instrument.retarget(mono, note[3][1], options) else mono = Instrument.voice(patch, {note[3][1]}, options) end
		else
			table.insert(voices, Instrument.voice(patch, note[3], options))
		end
	end
	render(frames)
	local sum = 0
	for k = 1, frames do sum = sum + out.left[k] ^ 2 + out.right[k] ^ 2 end
	return math.sqrt(sum / (2 * frames))
end

--- The level at which `patch` would play its role's phrase at the target.
function Calibration.level(patch, role)
	local measured = Calibration.measure(patch, role)
	return patch.level * Calibration.targets[role or patch.role] / measured
end

--- Decibels `patch` sits from its role's target.
function Calibration.offset(patch, role)
	return 20 * math.log(Calibration.measure(patch, role) / Calibration.targets[role or patch.role], 10)
end

return Calibration
