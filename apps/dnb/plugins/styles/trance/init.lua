-- Trance: Uplifting, Progressive and Psy tracks at 138. A punchy kick on
-- every beat, an off-beat bass (galloping 16ths in Psy), wide supersaw pads
-- through long breakdowns, a gated 16th arpeggio climbing the chord and an
-- anthem lead that returns, full, on the drop after the breakdown.

local FLAVOURS = {
	{id = "uplifting", name = "Uplifting", gallop = false, lead = 1, arp = 1},
	{id = "progressive", name = "Progressive", gallop = false, lead = 0.5, arp = 0.8},
	{id = "psy", name = "Psytrance", gallop = true, lead = 0.3, arp = 0.6},
}
-- Trance lives for the breakdown: long, with the pads and melody alone.
local ARRANGEMENT = {introBars = 16, buildBars = 8, dropBars = 32, breakdownBars = 24, rebuildBars = 8,
	outroBars = 16, blendBars = 8, minCycles = 2, maxCycles = 2}
-- The trance cadences: i–VI–III–VII and its relatives, two bars a chord.
local PROGRESSIONS = {{1, 6, 3, 7}, {6, 7, 1, 1}, {1, 6, 7, 5}, {1, 4, 6, 7}, {6, 4, 1, 7}}
local ARP_ORDERS = {{1, 2, 3, 4, 5, 4, 3, 2}, {1, 3, 2, 4, 3, 5, 4, 6}, {1, 2, 3, 5, 1, 2, 4, 5}, {1, 4, 3, 5, 2, 4, 3, 6}}

local function buildCycle(kit, rng, track)
	local mode, flavour = track.mode, track.flavour
	local progression = kit.stableProgression(mode, rng.pick(PROGRESSIONS))
	return {
		progression = progression,
		voicings = kit.voicings(mode, progression, {0, 2, 4, 8}), -- add9: the open trance sound
		arp = rng.pick(ARP_ORDERS),
		gate = {},
		leadOn = rng.chance(flavour.lead), arpOn = rng.chance(flavour.arp),
		lead = kit.melody(rng),
	}
end

-- Later cycles build new arps but keep the anthem: the first cycle's
-- melody, progression and voicing return after every breakdown.
local function material(kit, rng, track, first)
	local cycle = buildCycle(kit, rng, track)
	if first then
		cycle.lead, cycle.progression, cycle.voicings, cycle.leadOn = first.lead, first.progression, first.voicings,
			first.leadOn
	end
	return cycle
end

-- The arrangement ------------------------------------------------------------

local function arrange(kit, track, cycles)
	local lanes = kit.lanes(track)
	kit.blendIn(lanes, track)
	for _, section in ipairs(track.sections) do
		local id, cycle = section.id, cycles[section.cycle]
		-- The arp runs from the intro's second phrase to the end of the track.
		if cycle.arpOn then lanes:within("arp", section, id == "intro" and 8 or 0, nil, "arp") end
		if id == "intro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("hats", section, 0, nil, "hats")
		elseif id == "build" then
			lanes:within("snare", section, 0, nil, "roll.snare")
			lanes:within("hats", section, 0, nil, "hats.full")
			lanes:within("sub", section, 4, nil, "sub.pulse")
			lanes:within("pads", section, 0, nil, "pads.chords")
		elseif id == "drop" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			lanes:within("hats", section, 0, nil, "hats.full")
			lanes:within("ride", section, 16, nil, "ride")
			lanes:within("percussion", section, 0, nil, "perc")
			lanes:within("sub", section, 0, nil, "sub.drive")
			lanes:within("reese", section, 0, nil, "reese")
			lanes:within("pads", section, 0, nil, "pads.chords")
			lanes:within("stabs", section, 16, nil, "stabs")
			-- The anthem waits for the drop's second half the first time round.
			if cycle.leadOn then lanes:within("lead", section, section.cycle > 0 and 0 or 16, nil, "lead") end
			lanes:phraseEnds("throws", section, 8, "throw")
		elseif id == "breakdown" then
			lanes:within("pads", section, 0, nil, "pads.chords")
			if cycle.leadOn then lanes:within("lead", section, 8, nil, "lead.soft") end
			lanes:phraseEnds("throws", section, 8, "throw")
		elseif id == "outro" then
			lanes:within("kick", section, 0, nil, "kick")
			lanes:within("snare", section, 0, nil, "clap")
			lanes:within("hats", section, 0, nil, "hats")
			lanes:within("sub", section, 0, 8, "sub.drive")
			lanes:within("reese", section, 0, 8, "reese")
		end
	end
	kit.punctuate(lanes, track, function() return "fill.roll" end)
	return lanes:done()
end

-- The patterns -----------------------------------------------------------------

local function hats(full)
	return function(_, ctx)
		for step = 2, 14, 4 do ctx.hit(step, "openHat", 0.5) end
		if full then
			for step = 0, 15 do if step % 4 ~= 2 then ctx.hit(step, "hat", step % 2 == 0 and 0.3 or 0.18) end end
		end
	end
end

local function lead(gain)
	return function(bar, ctx)
		for _, note in ipairs(ctx.cycle.lead[ctx.phraseBar % 4 + 1]) do
			table.insert(bar.lead, {step = note.step, length = note.length, glide = note.glide, gain = gain,
				note = ctx.kit.leadPitch(ctx.mode, ctx.tonic, ctx.chord.degree, note.offset), throw = ctx.throw})
		end
	end
end

local PATTERNS = {
	{id = "kick", part = "kick", render = function(_, ctx)
		for step = 0, 12, 4 do
			if not (ctx.fill and step == 12) then ctx.hit(step, "kick", 1) end
		end
	end},
	{id = "clap", part = "snare", render = function(_, ctx)
		ctx.hit(4, "clap", 0.75)
		ctx.hit(12, "clap", 0.75, {throw = ctx.throw})
	end},
	{id = "fill.roll", part = "fills", render = function(_, ctx)
		ctx.fill = "roll"
		for step = 12, 15.5, 0.5 do ctx.hit(step, "snare", 0.3 + 0.1 * (step - 12)) end
	end},
	{id = "hats", part = "hats", render = hats(false)},
	{id = "hats.full", part = "hats", render = hats(true)},
	{id = "ride", part = "ride", render = function(_, ctx)
		for step = 2, 15, 4 do ctx.hit(step, "ride", 0.35) end
	end},
	{id = "perc", part = "percussion", render = function(_, ctx)
		if ctx.complexity <= 0.4 then return end
		for _, step in ipairs({3, 7, 11, 15}) do if step ~= 7 or ctx.complexity > 0.7 then ctx.hit(step, "shaker", 0.3) end end
	end},
	-- The off-beat bass, or Psytrance's gallop filling every 16th but the kick.
	{id = "sub.drive", part = "sub", render = function(bar, ctx)
		local gallop = ctx.flavour.gallop
		for step = 0, 15 do
			local offbeat = step % 4 == 2
			if offbeat or (gallop and step % 4 ~= 0 and (ctx.energy > 0.3 or offbeat)) then
				table.insert(bar.bass, {step = step, length = offbeat and not gallop and 1.6 or 0.8,
					note = ctx.chord.root + 12, reese = 0.9, accent = offbeat and gallop or nil, subOnly = true})
			end
		end
	end},
	{id = "sub.pulse", part = "sub", render = function(bar, ctx)
		for step = 2, 14, 4 do table.insert(bar.bass, {step = step, length = 1, note = ctx.chord.root + 12, subOnly = true}) end
	end},
	{id = "stabs", part = "stabs", render = function(bar, ctx)
		if ctx.energy > 0.5 then table.insert(bar.stabs, {step = 0, notes = ctx.chord.notes}) end
	end},
	{id = "arp", part = "arp", render = function(bar, ctx)
		local order, notes = ctx.cycle.arp, ctx.chord.notes
		local breakdown = ctx.section == "breakdown"
		for step = 0, 15 do
			if step % 2 == 0 or ctx.complexity > 0.3 or breakdown then
				local index = order[(step % #order) + 1]
				table.insert(bar.arp, {step = step, note = notes[(index - 1) % 4 + 1] + 12 * (1 + (index - 1) // 4),
					length = 0.7, gain = step % 4 == 0 and 1 or 0.65, pan = step % 2 == 0 and 0.3 or 0.7})
			end
		end
	end},
	{id = "lead", part = "lead", bars = 4, render = lead(1)},
	{id = "lead.soft", part = "lead", bars = 4, render = lead(0.7)},
}

return {
	api = 2,
	title = "Trance",
	symbol = "sparkles",
	summary = "Uplifting, Progressive and Psy, with long breakdowns",
	tempo = {min = 132, max = 145, default = 138},
	defaults = {energy = 0.7, complexity = 0.6, swing = 0, humanize = 0.1,
		cutoff = 0.4, wobble = 0, drive = 0.3, space = 0.6},
	sound = {
		kick = {base = 48, sweep = 150, sweepTime = 0.02, decay = 0.2, drive = 2.2, click = 0.45, length = 0.35},
		hat = {scale = 2, decay = 0.012, openDecay = 0.06},
		bass = {detune = 0.003, resonance = 0.55, envAmount = 2, envDecay = 0.05},
		pad = {detune = 0.012, attack = 0.6, release = 1.4, brightness = 0.09},
		pluck = {decay = 0.07, sweep = 0.03, send = 1.1},
		lead = {detune = 0.008, brightness = 0.16, sweep = 0.3, vibratoDepth = 0.009, send = 0.8},
		mix = {duckDepth = 0.7, pad = 0.07, arp = 0.09, lead = 0.08, delayFeedback = 0.45, reverbSend = 1.1},
	},
	set = {flavours = FLAVOURS, modes = {"minor", "phrygian"}, arrangement = ARRANGEMENT, modulations = {2, 0}},
	material = material,
	arrange = arrange,
	patterns = PATTERNS,
}
