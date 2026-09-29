-- The promo's score at 120 BPM, generated from the same timeline as the
-- picture: D major, bright and forward. A pulse under the montage, a drop
-- as the window lands in the display (3.5 s), a lighter groove while the
-- agent works in Lua Studio, a breath under "Zero compile cycle" (11 s),
-- the drop back in with "Talk" (14 s), the biggest hit as the film passes
-- through the phone into the game (21.8 s), sixteenths for the speed run
-- and a bell chord on the logo. Pops and slams come from the reel's own
-- events; coins ring when the game's replay takes them; typing ticks follow
-- the characters Lua Studio reveals.
local Audio = require("reel.audio")
local I = require("reel.instruments")

local Score = {}

local BEAT, BAR = 0.5, 2
local hz = Audio.midiHz

local D = { root = 38, pad = { 57, 62, 66, 69, 73 } }
local BM = { root = 47, pad = { 54, 59, 62, 66, 69 } }
local G = { root = 43, pad = { 55, 59, 62, 66, 71 } }
local A = { root = 45, pad = { 57, 61, 64, 69, 71 } }
local EM = { root = 40, pad = { 55, 59, 62, 64, 67 } }
local FSM = { root = 42, pad = { 54, 57, 61, 64, 69 } }
local BARS = { D, BM, G, A, D, BM, G, A, EM, FSM, G, A, D, BM, D }

local function chord(t)
	return BARS[math.min(#BARS, math.max(1, math.floor(t / BAR) + 1))]
end

-- The sections, in the picture's order.
local SECTIONS = {
	{ 0, "intro" }, { 3.5, "drop" }, { 6.0, "studio" }, { 11.0, "break" }, { 14.0, "talk" },
	{ 17.0, "drop" }, { 20.3, "rise" }, { 21.8, "game" }, { 25.0, "speed" }, { 27.8, "end" },
}
local function section(t)
	local name = "intro"
	for _, s in ipairs(SECTIONS) do if t >= s[1] then name = s[2] end end
	return name
end

local GROOVE = { drop = true, studio = true, talk = true, game = true, speed = true }

-- Score.render(reel, music, duration, sampleRate) -> left, right.
-- music = {kicks, crashes, booms, risers, typing, sends, coins, hits, logo}.
function Score.render(reel, music, duration, sampleRate)
	local m = Audio.new(duration, sampleRate)
	local events = { pop = {}, slam = {}, whoosh = {} }
	for _, e in ipairs(reel.events) do
		if events[e.kind] then table.insert(events[e.kind], e) end
	end

	-- Pad: one voicing per bar; the last two ring out under the logo.
	local padLevel = { intro = 0.8, drop = 0.45, studio = 0.55, ["break"] = 1.0, talk = 0.5, rise = 0.7, game = 0.45,
		speed = 0.4, ["end"] = 1.05 }
	for b, c in ipairs(BARS) do
		I.pad(m, (b - 1) * BAR, BAR, c.pad, {
			last = b >= #BARS - 1,
			level = function(t) return padLevel[section(t)] end,
			bright = function(t) return section(t) == "intro" and 0.35 + 0.5 * t / 3.5 or 1 end,
		})
	end

	-- Plucked arpeggio: eighths in the quiet sections, sixteenths in the
	-- grooves and the run.
	local pattern = { 0, 2, 4, 1, 3, 4, 2, 1 }
	local levels = { intro = 0.05, drop = 0.05, studio = 0.045, ["break"] = 0.06, talk = 0.05, rise = 0.055,
		game = 0.06, speed = 0.055 }
	local step, at = 0, 0
	while at < 27.8 do
		local sec = section(at)
		local c = chord(at)
		local note = c.pad[pattern[step % #pattern + 1] % #c.pad + 1] + 12
		local accent = step % 4 == 0 and 1.0 or (step % 2 == 0 and 0.8 or 0.62)
		I.pluck(m, at, hz(note), {
			level = (levels[sec] or 0.05) * accent, bright = sec == "intro" and 0.25 + 0.75 * at / 3.5 or 1,
			pan = step % 2 == 0 and 0.32 or 0.68, send = 0.5,
		})
		step = step + 1
		local slow = sec == "intro" or sec == "break" or sec == "studio"
		at = at + (slow and BEAT / 2 or BEAT / 4)
	end

	-- Bass: pumping eighths in the grooves, long notes in the break.
	for b = 2, 14 do
		local c, t0 = BARS[b], (b - 1) * BAR
		local sec = section(t0 + 0.01)
		if sec == "break" or sec == "rise" then
			for half = 0, 1 do I.bassSustain(m, t0 + half * BAR / 2, hz(c.root), BAR / 2) end
		elseif GROOVE[sec] then
			for e = 0, 7 do I.bass(m, t0 + e * BEAT / 2, hz(c.root + (e % 4 == 3 and 12 or 0)), BEAT / 2 - 0.01) end
		end
	end

	-- Drums, in a fixed order so the mix repeats exactly.
	for _, k in ipairs(music.kicks) do I.kick(m, k) end
	for b = 2, 14 do
		local t0 = (b - 1) * BAR
		if GROOVE[section(t0 + 0.01)] then
			I.clap(m, t0 + 0.5)
			I.clap(m, t0 + 1.5)
			for s = 0, 15 do
				local t = t0 + s * BEAT / 4
				local open = s % 4 == 2
				if open or section(t) == "speed" or section(t) == "game" or s % 2 == 0 then
					I.hat(m, t, open, open and 0.05 or (s % 2 == 1 and 0.035 or 0.022), open and 0.62 or 0.4)
				end
			end
		end
	end
	for _, c in ipairs(music.crashes) do I.crash(m, c, c == 3.5 or c == 21.8 or c == music.logo) end
	for _, r in ipairs(music.risers) do I.riser(m, r[1], r[2]) end
	for _, b in ipairs(music.booms) do I.boom(m, b[1], b[2]) end

	-- The picture's own events.
	for _, w in ipairs(events.whoosh) do I.whoosh(m, w.time, w["until"] or w.time + 0.3) end
	for _, s in ipairs(events.slam) do I.slam(m, s.time) end
	for j, p in ipairs(events.pop) do
		local c = chord(p.time)
		I.blip(m, p.time, hz(c.pad[(j - 1) % #c.pad + 1] + 24), 0.3 + 0.4 * ((j - 1) % 3) / 2)
	end
	-- Window flips and device moves: soft whooshes.
	for _, w in ipairs(music.whooshes) do I.whoosh(m, w[1], w[2]) end
	-- Typing in the composer: a tick per character revealed.
	for _, run in ipairs(music.typing) do
		for i = 0, run.count - 1 do
			local t = run.from + (run.to - run.from) * i / run.count
			I.tone(m, t, hz(96 + (i % 3)), { length = 0.03, decay = 0.012, level = 0.018, pan = 0.62, send = 0.1 })
		end
	end
	-- Sending: a rising pair, then the agent's answer lands.
	for _, t in ipairs(music.sends) do
		I.tone(m, t, hz(81), { length = 0.2, decay = 0.08, level = 0.05, pan = 0.6, send = 0.4 })
		I.tone(m, t + 0.07, hz(88), { length = 0.3, decay = 0.12, level = 0.05, pan = 0.6, send = 0.5 })
	end
	-- Coins the game's replay takes: its own ring, pitched up the chord.
	for j, t in ipairs(music.coins) do
		for k, note in ipairs({ 88, 93 }) do
			I.tone(m, t + (k - 1) * 0.06, hz(note + (j - 1) * 2), { length = 0.5, decay = 0.18, level = 0.06, pan = 0.45, send = 0.5 })
		end
	end
	-- The speed run: a hit on every edit.
	for _, t in ipairs(music.hits) do I.slam(m, t) end
	-- The logo: a bell chord, arpeggiated.
	local bellPans = { 0.5, 0.3, 0.7, 0.4, 0.6 }
	for j, note in ipairs({ 74, 78, 81, 86, 90 }) do I.bell(m, music.logo + (j - 1) * 0.11, hz(note), bellPans[j]) end

	return m:master({
		kicks = music.kicks,
		gain = function(t)
			local g = math.min(1, t / 0.02)
			-- Breaths before the two drops.
			if (t >= 3.44 and t < 3.5) or (t >= 21.74 and t < 21.8) then g = g * 0.08 end
			if t > duration - 0.8 then g = g * Audio.fadeOut(t, duration - 0.8, duration) end
			return g
		end,
	})
end

return Score
