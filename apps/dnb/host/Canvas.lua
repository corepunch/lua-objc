-- The canvas: a track as one long stretch of 4–5 minutes, not a form of
-- named sections. What it holds is an energy curve, a handful of anchors
-- (low at the mix-in, up through plateaus, one valley, a late second peak,
-- low again at the mix-out) drawn per track and read phrase by phrase (see
-- docs/research/dance-music-arrangement.md). From the curve the arranger
-- decides, one phrase of eight bars at a time:
--   which layers play: the layers of a genre enter in an order (drums,
--     then bass and tops, then chords, melody …) and the curve says how
--     many are on; a valley sends the drums out and keeps the harmony;
--   what each layer plays: a block picked by tag from the track's palette,
--     the nearest in energy to the moment, held until the curve moves or a
--     swap comes (blocks of one palette are what the track is remembered by);
--   what happens at the edges: a riser and an impact before and after a
--     big rise (only in genres that use them), a fill ending a phrase, the
--     drums or the bass dropping out for the last bars, a half-time phrase,
--     a layer fading in through a filter.
-- Changes land on phrase boundaries, so nothing enters off the grid. The
-- result is lanes of blocks (host/Lanes.lua → host/Arrangement.lua) and the
-- events the timeline names ("Breakdown in 8 bars").
local Model = require("apps.dnb.Model")
local Lanes = require("apps.dnb.host.Lanes")

local Canvas = {}

--- What a style or flavour leaves out of its `arc`.
Canvas.defaults = {
	minutes = {4, 5},
	phrase = 8,          -- bars: layers change on these boundaries
	unit = 16,           -- bars: a track is a whole number of these
	intro = 16,          -- bars at either end that keep to drums, tops and texture
	outro = 16,
	blend = 8,           -- bars of the new track's start that carry the old one's chord
	-- Energy by the fraction of the track: low in, a first peak, a valley,
	-- a second and higher peak, a long step down.
	curve = {{0, 0.25}, {0.12, 0.4}, {0.25, 0.65}, {0.38, 0.85}, {0.5, 0.4}, {0.6, 0.9}, {0.8, 0.65}, {0.9, 0.4}, {1, 0.2}},
	jitter = 0.04,       -- how far an anchor may move, as a fraction of the track and of energy
	valley = 0.45,       -- phrases below this energy, between the ends, are a breakdown
	drumless = 0.8,      -- the share of breakdowns the drums leave entirely
	bassOut = 0.5,       -- … and the bass too
	riser = 0.8, riserBars = {4, 8}, roll = 0.5, impact = 0.7,
	fill = 0.6,          -- the share of phrases that end on a drum fill (more at 16 bars)
	kickOut = 0.3, kickOutBars = {1, 2, 4},
	swap = 0.35,         -- the share of 16-bar boundaries that bring another block
	halftime = 0.25,
	fadeIn = 0.5, morph = 0.4,
	lift = 0,            -- the share of tracks whose second peak is a key higher
	-- The order layers enter in; a tier is shuffled per track.
	layers = {{"drums"}, {"bass", "tops"}, {"pad", "stab", "keys"}, {"arp", "lead"}, {"counter", "texture"}},
	-- What plays in a breakdown, harmony first.
	breakdown = {"pad", "keys", "lead", "arp", "counter", "texture", "stab"},
}
local ENDS = {drums = true, tops = true, texture = true}
-- Layers that fade in through a filter when they enter.
local FADES = {bass = true, pad = true, stab = true, arp = true, lead = true, keys = true, counter = true}
local FILTER = {intro = 0.3, entry = 0.3, morph = 0.6}
-- How loud the mix-in and mix-out may be: from `low` at the very end to
-- `low + rise` where the groove proper begins.
local EDGE = {low = 0.25, rise = 0.25}

-- How many blocks of a role a track's palette keeps.
-- The kinds of fx block a palette holds, sorted.
local FX_KINDS = {"crash", "downlifter", "impact", "riser"}
local SIZE = {bass = 3, tops = 2, pad = 2, keys = 2, stab = 2, arp = 2, lead = 2, counter = 1, texture = 1}
-- How far a block's energy may sit from the moment's before it is changed.
local TOLERANCE = 0.25

local function merged(base, over)
	local result = {}
	for k, v in pairs(base or {}) do result[k] = v end
	for k, v in pairs(over or {}) do result[k] = v end
	return result
end

--- The arc of a track: the defaults, a style's, then a flavour's.
function Canvas.arc(...)
	local arc = merged(Canvas.defaults)
	for i = 1, select("#", ...) do
		local over = select(i, ...)
		for k, v in pairs(over or {}) do
			assert(Canvas.defaults[k] ~= nil, "unknown arc field " .. tostring(k))
			arc[k] = v
		end
	end
	return arc
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- The anchors with their places and energies moved a little.
local function anchors(arc, rng)
	local list = {}
	for i, anchor in ipairs(arc.curve) do
		local t, e = anchor[1], anchor[2]
		if i > 1 and i < #arc.curve then t = t + (rng.float() * 2 - 1) * arc.jitter end
		e = clamp(e + (rng.float() * 2 - 1) * arc.jitter, 0.1, 1)
		list[i] = {t, e}
	end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	return list
end

local function along(list, t)
	for i = 2, #list do
		if t <= list[i][1] then
			local a, b = list[i - 1], list[i]
			local span = b[1] - a[1]
			return span <= 0 and b[2] or a[2] + (b[2] - a[2]) * (t - a[1]) / span
		end
	end
	return list[#list][2]
end

-- A word for what a phrase does.
local function label(phrase, before, after, ends)
	if phrase.start < ends.intro then return "Mix in" end
	if phrase.start + phrase.length > ends.length - ends.outro then return "Mix out" end
	if phrase.valley then return "Breakdown" end
	if before and phrase.energy - before.energy >= 0.2 then return "Lift" end
	if phrase.energy >= 0.8 then return "Peak" end
	if after and after.energy - phrase.energy <= -0.2 then return "Release" end
	return "Groove"
end

--- A track's length in bars and its phrases {start, length, energy,
--- valley, edge, label}, drawn from `rng`, and where its key lifts (or nil)
--- by a choice of `modulations`.
function Canvas.layout(arc, tempo, modulations, rng)
	local minutes = rng.between(arc.minutes)
	local bars = math.floor(minutes * tempo / 4 / arc.unit + 0.5) * arc.unit
	bars = math.max(bars, 4 * arc.unit)
	local count = bars // arc.phrase
	local list = anchors(arc, rng)
	local phrases, peak = {}, 0
	for p = 0, count - 1 do
		local start = p * arc.phrase
		local energy = along(list, (p + 0.5) / count)
		local edge = start < arc.intro or start + arc.phrase > bars - arc.outro
		-- The ends are for mixing: the curve may not climb in them faster
		-- than the bars allow, whatever the length of intro and outro.
		if edge then
			local middle = start + arc.phrase / 2
			local into = start < arc.intro and middle / arc.intro or (bars - middle) / arc.outro
			energy = math.min(energy, EDGE.low + EDGE.rise * clamp(into, 0, 1))
		end
		-- A valley is a fall from a peak, not the low start of a climb.
		table.insert(phrases, {start = start, length = arc.phrase, energy = energy, edge = edge,
			valley = not edge and energy < arc.valley and peak - energy >= 0.2})
		peak = math.max(peak, energy)
	end
	local ends = {intro = arc.intro, outro = arc.outro, length = bars}
	for p, phrase in ipairs(phrases) do phrase.label = label(phrase, phrases[p - 1], phrases[p + 1], ends) end
	-- The second peak: the first phrase of high energy after a valley.
	local lift
	local lifts = {}
	for _, semis in ipairs(modulations) do
		if semis ~= 0 then table.insert(lifts, semis) end
	end
	if arc.lift > 0 and #lifts > 0 and rng.chance(arc.lift) then
		local seen = false
		for _, phrase in ipairs(phrases) do
			seen = seen or phrase.valley
			if seen and not phrase.valley and phrase.energy >= 0.75 and not lift then
				lift = {bar = phrase.start, semis = rng.pick(lifts)}
			end
		end
	end
	return bars, phrases, lift
end

-- The blocks of `role` a track draws on --------------------------------------

local function wantsOf(spec, field)
	local set = {}
	for _, tag in ipairs(spec[field] or {}) do set[tag] = true end
	return set
end

local function score(block, wants, rng, before)
	local value = rng.float() * 0.8 + (block.flavours and 0.3 or 0)
	local hits = 0
	for tag in pairs(wants) do
		if block.tags[tag] then hits = hits + 1 end
	end
	value = value + 0.5 * math.min(hits, 2)
	if before and before[block.id] then value = value - 1 end
	return value
end

-- `count` of `candidates` that cover the energy range: the best by score
-- first, then each next the one best by score and farthest in energy from
-- those taken.
local function spread(candidates, count, wants, rng, before)
	local scored = {}
	for _, block in ipairs(candidates) do table.insert(scored, {block = block, score = score(block, wants, rng, before)}) end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.block.id < b.block.id
	end)
	local chosen = {}
	if #scored > 0 then table.insert(chosen, scored[1].block) end
	while #chosen < math.min(count, #scored) do
		local best, bestValue
		for _, each in ipairs(scored) do
			local taken, far = false, 1
			for _, block in ipairs(chosen) do
				if block == each.block then taken = true end
				far = math.min(far, math.abs(block.energy - each.block.energy))
			end
			local value = each.score + 2.5 * far
			if not taken and (not bestValue or value > bestValue) then best, bestValue = each.block, value end
		end
		table.insert(chosen, best)
	end
	return chosen
end

local function best(candidates, wants, rng, before, accept)
	local pool = {}
	for _, block in ipairs(candidates) do
		if accept(block) then table.insert(pool, block) end
	end
	return spread(pool, 1, wants, rng, before)[1]
end

--- The blocks a track draws on, by role: `palette[role]` a list, and
--- `palette.halftime` a half-time drum block when there is one to switch
--- to; `palette.fx[kind]` lists of fx blocks. `before` is the previous
--- track's palette: its blocks are passed over where there is a choice.
function Canvas.palette(track, catalogue, genre, rng, before)
	local palette, used = {fx = {}}, {}
	for _, list in pairs(before or {}) do
		if list[1] then for _, block in ipairs(list) do used[block.id] = true end end
	end
	for kind, list in pairs(before and before.fx or {}) do
		for _, block in ipairs(list) do used[block.id] = true end
	end
	for _, channel in ipairs(track.channels) do
		local role, spec = channel.role, channel.spec
		local wants = wantsOf(spec, "wants")
		local candidates = catalogue:candidates(role, genre, track.flavour.id, wantsOf(spec, "avoid"))
		assert(#candidates > 0, string.format("%s %s has no %s blocks", genre, track.flavour.id, role))
		if role == "drums" then
			local plain, half = {}, {}
			for _, block in ipairs(candidates) do
				table.insert((block.tags.halftime and not wants.halftime) and half or plain, block)
			end
			if #plain == 0 then plain, half = half, {} end
			local chosen = {}
			-- A quiet loop to mix in and out on, a loud one, and a middle.
			local quiet = best(plain, wants, rng, used, function(b) return b.energy < 0.5 and b.tags.mixable end)
				or best(plain, wants, rng, used, function(b) return b.energy < 0.5 end) or plain[1]
			table.insert(chosen, quiet)
			local loud = best(plain, wants, rng, used, function(b) return b.energy >= 0.7 and b ~= quiet end)
			if loud then table.insert(chosen, loud) end
			local middle = best(plain, wants, rng, used, function(b)
				return b.energy >= 0.4 and b.energy < 0.7 and b ~= quiet and b ~= loud
			end)
			if middle then table.insert(chosen, middle) end
			local more = best(plain, wants, rng, used, function(b)
				for _, taken in ipairs(chosen) do if taken == b then return false end end
				return true
			end)
			if more then table.insert(chosen, more) end
			palette.drums = chosen
			palette.halftime = #half > 0 and best(half, wants, rng, used, function(b) return b.energy >= 0.5 end)
				or half[1] or nil
		elseif role == "fx" then
			-- In a fixed order: each kind draws from the track's stream.
			for _, kind in ipairs(FX_KINDS) do
				local pool = {}
				for _, block in ipairs(candidates) do
					if block.kind == kind then table.insert(pool, block) end
				end
				if #pool > 0 then palette.fx[kind] = spread(pool, 2, wants, rng, used) end
			end
			palette.fx.any = candidates
		else
			palette[role] = spread(candidates, SIZE[role] or 2, wants, rng, used)
		end
	end
	return palette
end

-- The layers of a track -------------------------------------------------------

-- The layers in the order they enter, tiers shuffled.
local function orderOf(track, arc, rng)
	local order = {}
	for _, tier in ipairs(arc.layers) do
		local roles = {}
		for _, role in ipairs(tier) do
			if track.byRole[role] then table.insert(roles, role) end
		end
		for _, role in ipairs(rng.shuffle(roles)) do table.insert(order, role) end
	end
	return order
end

-- Which layers play in each phrase.
local function activity(track, arc, order, rng)
	local sets, hi, current, last = {}, #order, 0, nil
	local breakdown = {}
	for _, role in ipairs(arc.breakdown) do
		if track.byRole[role] then table.insert(breakdown, role) end
	end
	for p, phrase in ipairs(track.phrases) do
		local energy = phrase.energy
		-- Every layer is on by an energy of 0.8; the first bars of a climb
		-- have one or two.
		local target = clamp(math.floor(hi * clamp((energy - 0.1) / 0.7, 0, 1) + 0.5), 1, hi)
		local big = last == nil or math.abs(energy - last) >= 0.25
		local step = big and hi or (phrase.start % 16 == 0 and 2 or 1)
		if target > current then current = math.min(target, current + step)
		elseif target < current then current = math.max(target, current - step) end
		last = energy
		local set = {}
		if phrase.valley and #breakdown > 0 and rng.chance(arc.drumless) then
			for i = 1, math.min(#breakdown, math.max(2, target + 1)) do set[breakdown[i]] = true end
			if track.byRole.bass and not rng.chance(arc.bassOut) then set.bass = true end
			phrase.drumless = true
		else
			for i = 1, current do set[order[i]] = true end
		end
		if phrase.edge then
			for role in pairs(set) do
				if not ENDS[role] then set[role] = nil end
			end
		end
		sets[p] = set
	end
	return sets
end

-- The block of `role` for a phrase of `energy`: the one it already plays
-- while that still suits, else the nearest in energy and density.
local function pick(palette, role, energy, current, rng, avoid, swap)
	local list = palette[role]
	if not list then return nil end
	local function cost(block)
		return math.abs(block.energy - energy) + 0.5 * math.abs(block.density - energy)
	end
	if current and not swap and math.abs(current.energy - energy) <= TOLERANCE then return current end
	local best, bestCost
	for _, block in ipairs(list) do
		local ok = true
		for tag in pairs(block.excludes) do if avoid.tags[tag] then ok = false end end
		for tag in pairs(avoid.excludes) do if block.tags[tag] then ok = false end end
		if swap and block == current and #list > 1 then ok = false end
		if ok then
			local c = cost(block) + rng.float() * 0.15
			if not bestCost or c < bestCost then best, bestCost = block, c end
		end
	end
	return best
end

-- Roles in the order they claim a phrase: the foundation first, so a
-- conflict is lost by the melody, not the kick.
local PRIORITY = {"drums", "bass", "tops", "stab", "keys", "pad", "arp", "lead", "counter", "texture"}

--- The DJ blend: through the first `blend` bars of a new track the
--- outgoing track's last chords keep sounding on the pad and, for the
--- first half, the bass, played on the outgoing track's patches.
function Canvas.blendIn(lanes, track, previous)
	if track.index == 0 or not previous then return end
	if previous.byRole.pad then lanes:add("pad", 0, track.blendBars, "pad.blend") end
	if previous.byRole.bass then lanes:add("bass", 0, track.blendBars // 2, "bass.blend") end
end

--- A track's lanes and events from its palette and curve. `previous` is
--- the track before it in the set; `rng` the arranger's stream. Events are
--- {bar, kind} for the timeline: "valley", "return", "lift", "riser",
--- "drumsOut", "halftime".
function Canvas.arrange(track, rng, previous)
	local arc, palette = track.arc, track.palette
	local lanes = Lanes.new(track)
	Canvas.blendIn(lanes, track, previous)
	local phrases = track.phrases
	local order = orderOf(track, arc, rng)
	local sets = activity(track, arc, order, rng)
	local events = {}
	local function event(bar, kind) table.insert(events, {bar = bar, kind = kind}) end

	-- Half-time phrases: a run of high-energy phrases the drums turn over.
	local halftime = {}
	if palette.halftime and arc.halftime > 0 and #palette.drums > 0 then
		for p, phrase in ipairs(phrases) do
			if not phrase.edge and not phrase.valley and phrase.energy >= 0.6 and sets[p].drums
				and not halftime[p - 1] and rng.chance(arc.halftime) then
				halftime[p] = true
				if phrases[p + 1] and phrases[p + 1].energy >= 0.6 and rng.chance(0.5) then halftime[p + 1] = true end
			end
		end
	end

	-- What each layer plays in each phrase.
	local picks, current, since = {}, {}, {}
	for p, phrase in ipairs(phrases) do
		picks[p] = {}
		local avoid = {tags = {}, excludes = {}}
		local boundary = phrase.start % 32 == 0 and 0.5 or (phrase.start % 16 == 0 and 1 or 0)
		for _, role in ipairs(PRIORITY) do
			if sets[p][role] and palette[role] then
				local block
				local swap = boundary > 0 and current[role] ~= nil and role ~= "drums" and rng.chance(arc.swap * boundary)
				if role == "drums" and halftime[p] then
					block = palette.halftime
				else
					block = pick(palette, role, phrase.energy, current[role], rng, avoid, swap)
				end
				if block then
					current[role] = block
					picks[p][role] = {block = block, variant = (role == "drums" and phrase.edge) and "light" or nil}
					for tag in pairs(block.tags) do avoid.tags[tag] = true end
					for tag in pairs(block.excludes) do avoid.excludes[tag] = true end
				end
			else
				current[role] = nil
			end
		end
	end

	-- Layers as runs of phrases playing one block.
	for _, role in ipairs(PRIORITY) do
		local run
		local function flush()
			if run then
				lanes:fill(role, run.start, run.length, run.block.id, {variant = run.variant})
				run = nil
			end
		end
		for p, phrase in ipairs(phrases) do
			local pick = picks[p][role]
			if pick and run and run.block == pick.block and run.variant == pick.variant then
				run.length = run.length + phrase.length
			else
				flush()
				if pick then run = {start = phrase.start, length = phrase.length, block = pick.block, variant = pick.variant} end
			end
		end
		flush()
	end

	local length = track.length
	local function rising(p) return phrases[p] and phrases[p - 1] and phrases[p].energy - phrases[p - 1].energy >= 0.2 end
	local function fx(kind) local list = palette.fx[kind]; return list and rng.pick(list) end
	local function groove(bar)
		local block = lanes:at("drums", bar)
		if block and not block.pattern:find("^drums%.") then return block end
	end

	-- The edges between phrases.
	for p = 2, #phrases do
		local phrase, before = phrases[p], phrases[p - 1]
		local start = phrase.start
		local dE = phrase.energy - before.energy
		local rolled = false
		if before.valley and not phrase.valley then event(start, "return") end
		if phrase.valley and not before.valley then event(start, "valley") end
		if rising(p) and not phrase.edge then
			local riser = arc.riser > 0 and fx("riser")
			if riser and sets[p - 1] and track.byRole.fx and rng.chance(arc.riser * (dE >= 0.3 and 1 or 0.6)) then
				local bars = math.min(rng.pick(arc.riserBars), before.length)
				lanes:replace("fx", start - bars, bars, riser.id)
				event(start - bars, "riser")
				if sets[p - 1].drums and rng.chance(arc.roll) then
					local under = groove(start - 1)
					local roll = math.min(bars, 4)
					if under then
						lanes:replace("drums", start - roll, roll, "drums.roll", {under = under.pattern})
						rolled = true
					end
				end
			end
			local impact = fx("impact")
			if impact and track.byRole.fx and rng.chance(arc.impact) then lanes:replace("fx", start, 1, impact.id) end
		elseif dE <= -0.25 and track.byRole.fx and not before.edge then
			local down = fx("downlifter")
			if down and rng.chance(0.5) then lanes:fill("fx", start - 2, 2, down.id) end
		end
		-- A fill ends the phrase.
		local chance = arc.fill * (start % 16 == 0 and 1.4 or 1)
		if not rolled and not phrase.edge and sets[p - 1].drums and rng.chance(chance) then
			local under = groove(start - 1)
			if under then
				lanes:replace("drums", start - 1, 1, "drums.fill", {under = under.pattern, phase = start - 1 - under.start
					+ (under.offset or 0)})
			end
		end
	end

	-- Drop-outs: the drums, and sometimes the bass, leave a phrase's last bars.
	local lastOut = -3
	for p = 1, #phrases - 1 do
		local phrase = phrases[p]
		local next = phrases[p + 1]
		-- Not in runs: a drop-out is a move, so a few phrases pass between.
		if p - lastOut >= 3 and not phrase.edge and not phrase.valley and phrase.energy >= 0.6
			and next.energy - phrase.energy < 0.2 and sets[p].drums and rng.chance(arc.kickOut) then
			lastOut = p
			local bars = math.min(rng.pick(arc.kickOutBars), phrase.length - 1)
			local from = phrase.start + phrase.length - bars
			if groove(from) then
				lanes:cut("drums", from, bars)
				lanes:cut("tops", from, bars)
				if bars >= 2 and rng.chance(arc.bassOut) then lanes:cut("bass", from, bars) end
				event(from, "drumsOut")
			end
		end
	end
	for p, phrase in ipairs(phrases) do
		if halftime[p] and not halftime[p - 1] then event(phrase.start, "halftime") end
	end

	-- Fades: the mix-in opens through a filter, layers open as they enter,
	-- long ones breathe.
	if track.byRole.drums and rng.chance(0.6) then
		lanes:automate("drums", 0, math.min(arc.intro, length), {filter = {kind = "lowpass", from = FILTER.intro, to = 1}})
	end
	for p, phrase in ipairs(phrases) do
		for _, role in ipairs(PRIORITY) do
			local entering = sets[p][role] and (p == 1 or not sets[p - 1][role])
			if entering and FADES[role] and p > 1 and rng.chance(arc.fadeIn) then
				lanes:automate(role, phrase.start, phrase.length,
					{filter = {kind = "lowpass", from = FILTER.entry, to = 1}})
			end
		end
	end
	for _, role in ipairs({"pad", "arp", "lead"}) do
		local lane = lanes.byPart[role]
		for _, block in ipairs(lane and lane.blocks or {}) do
			if block.length >= 16 and not block.filter and rng.chance(arc.morph) then
				lanes:automate(role, block.start, 16, {filter = {kind = "lowpass", from = FILTER.morph, to = 1}})
			end
		end
	end
	-- The mix-out closes the bass down for the next track to mix over.
	local from = math.max(0, length - arc.outro)
	lanes:automate("bass", from, length - from, {filter = {kind = "lowpass", from = 1, to = 0.35}})
	if track.lift then event(track.lift.bar, "lift") end
	table.sort(events, function(a, b) return a.bar < b.bar end)
	return lanes:done(), events
end

return Canvas
