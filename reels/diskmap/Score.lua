-- The Diskmap score at 120 BPM: B minor build → drop on D at 4 s →
-- breakdown at 20 s → final lift at 24 s → D major landing on the logo at
-- 26 s. Picture-synced sounds (pops, slams, whooshes, the counter run, the
-- logo bell) come from the reel's own events; the groove is musical data.
local Audio = require("reel.audio")
local I = require("reel.instruments")

local Score = {}

local BEAT, BAR = 0.5, 2
local hz = Audio.midiHz

local BM = { root = 47, pad = { 54, 59, 62, 66, 69 } }
local G = { root = 43, pad = { 55, 59, 62, 66, 71 } }
local D = { root = 38, pad = { 57, 62, 64, 66, 69 } }
local A = { root = 45, pad = { 57, 61, 64, 69, 71 } }
local EM = { root = 40, pad = { 55, 59, 62, 64, 67 } }
local BARS = { BM, G, D, A, BM, G, D, A, BM, G, EM, A, BM, D, D }

local function chord(t)
	return BARS[math.min(#BARS, math.max(1, math.floor(t / BAR) + 1))]
end

local function section(t)
	if t < 4 then return "intro" end
	if t < 20 then return "drop" end
	if t < 24 then return "break" end
	if t < 26 then return "lift" end
	return "end"
end

-- Score.render(reel, music) -> left, right. `music` = {kicks, crashes,
-- risers, rolls, booms, drop, finish}.
function Score.render(reel, music, duration, sampleRate)
	local m = Audio.new(duration, sampleRate)
	local events = { pop = {}, slam = {}, whoosh = {}, counter = {}, logo = {} }
	for _, e in ipairs(reel.events) do
		if events[e.kind] then table.insert(events[e.kind], e) end
	end

	-- Pad: one voicing per bar, crossfading; the last two ring out.
	local padLevel = { intro = 0.9, drop = 0.5, ["break"] = 0.95, lift = 0.6, ["end"] = 1.05 }
	for b, c in ipairs(BARS) do
		local t0 = (b - 1) * BAR
		I.pad(m, t0, BAR, c.pad, {
			last = b >= #BARS - 1,
			level = function(t) return padLevel[section(t)] end,
			bright = function(t) return section(t) == "intro" and 0.35 + 0.5 * t / 4 or 1 end,
		})
	end

	-- Plucked arpeggio: 8ths in the intro and breakdown, 16ths in the drops.
	local pattern = { 0, 2, 4, 1, 3, 4, 2, 1 }
	local base = { drop = 0.05, ["break"] = 0.06, lift = 0.065 }
	local step, at = 0, 0.0
	while at < music.finish do
		local t = at
		local sec = section(t)
		local c = chord(t)
		local note = c.pad[pattern[step % #pattern + 1] % #c.pad + 1] + 12
		local accent = step % 4 == 0 and 1.0 or (step % 2 == 0 and 0.8 or 0.62)
		local level = sec == "intro" and 0.05 + 0.03 * t / 4 or (base[sec] or 0.05)
		I.pluck(m, t, hz(note), {
			level = level * accent, bright = sec == "intro" and 0.2 + 0.8 * t / 4 or 1,
			pan = step % 2 == 0 and 0.32 or 0.68, send = 0.5,
		})
		step = step + 1
		at = at + ((sec == "intro" or sec == "break") and BEAT / 2 or BEAT / 4)
	end

	-- Bass: pumping 8ths in the drops, long notes in the breakdown.
	for b = 3, 13 do
		local c, t0 = BARS[b], (b - 1) * BAR
		if section(t0) == "break" then
			for half = 0, 1 do I.bassSustain(m, t0 + half * BAR / 2, hz(c.root), BAR / 2) end
		else
			for e = 0, 7 do
				I.bass(m, t0 + e * BEAT / 2, hz(c.root + (e % 4 == 3 and 12 or 0)), BEAT / 2 - 0.01)
			end
		end
	end

	-- Drums. Noise voices run in a fixed order so the mix is repeatable.
	for _, k in ipairs(music.kicks) do I.kick(m, k) end
	local claps = {}
	for b = 3, 13 do
		if section((b - 1) * BAR) ~= "break" then
			table.insert(claps, (b - 1) * BAR + 0.5)
			table.insert(claps, (b - 1) * BAR + 1.5)
		end
	end
	for _, t in ipairs(music.claps) do table.insert(claps, t) end
	for _, c in ipairs(claps) do I.clap(m, c) end
	for b = 3, 13 do
		if section((b - 1) * BAR) ~= "break" then
			for s = 0, 15 do
				local open = s % 4 == 2
				if open or b >= 5 then
					I.hat(m, (b - 1) * BAR + s * BEAT / 4, open,
						open and 0.05 or (s % 2 == 1 and 0.035 or 0.022), open and 0.62 or 0.4)
				end
			end
		end
	end
	for _, c in ipairs(music.crashes) do I.crash(m, c, c == music.drop or c == music.logo) end
	for _, r in ipairs(music.rolls) do I.roll(m, r[1], r[2]) end

	-- Risers, whooshes and slams.
	for _, r in ipairs(music.risers) do I.riser(m, r[1], r[2]) end
	for _, w in ipairs(events.whoosh) do I.whoosh(m, w.time, w["until"] or w.time + 0.3) end
	for _, s in ipairs(events.slam) do I.slam(m, s.time) end
	for _, b in ipairs(music.booms) do I.boom(m, b[1], b[2]) end

	-- UI pops, pitched to the chord so the cascades sing.
	for j, p in ipairs(events.pop) do
		local c = chord(p.time)
		I.blip(m, p.time, hz(c.pad[(j - 1) % #c.pad + 1] + 24), 0.3 + 0.4 * ((j - 1) % 3) / 2)
	end
	-- The counter: a bright run up the chord.
	for _, e in ipairs(events.counter) do
		for j, note in ipairs({ 74, 78, 81, 86, 90 }) do
			I.tone(m, e.time + (j - 1) * 0.045, hz(note), { length = 0.8, decay = 0.3, level = 0.05, pan = 0.3 + 0.1 * (j - 1), send = 0.6 })
		end
	end
	-- The logo: a bell chord, arpeggiated.
	local bellPans = { 0.5, 0.3, 0.7, 0.4, 0.6 }
	for _, e in ipairs(events.logo) do
		for j, note in ipairs({ 74, 78, 81, 88, 90 }) do I.bell(m, e.time + (j - 1) * 0.11, hz(note), bellPans[j]) end
	end

	return m:master({
		kicks = music.kicks,
		gain = function(t)
			local g = math.min(1, t / 0.02)
			if t >= music.drop - 0.06 and t < music.drop then g = g * 0.08 end -- a breath before the drop
			if t > duration - 0.8 then g = g * Audio.fadeOut(t, duration - 0.8, duration) end
			return g
		end,
	})
end

return Score
