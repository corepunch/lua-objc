-- Component motion for the promo's screens. Screenshots are never shown
-- whole and still: they are cut into their components (Regions.lua) and the
-- components move.
--
--   Motion.phone(...)   the iPhone's screen through a timeline of app states:
--                       assembled from its pieces, then each change a
--                       matched-geometry morph (every task row keeps its
--                       identity, slides to its new place lifted on a soft
--                       shadow; new components pop in on a spring; removed
--                       ones fall away), with taps and the chat drawer
--   Motion.studio(...)  Lua Studio on the iPad: the prompt typed, the bubble
--                       flying up from the composer, the answer rising, the
--                       change card popping, the diff lines wiping in
--
-- Everything is a function of t, drawn with the reel's pen in the screen's
-- points (402 × 874 for the phone, 1376 × 1032 for the iPad).
local Reel = require("Reel")
local Regions = require("Regions")

local Shape, rgb = Reel.Shape, Reel.rgb
local curves = Reel.curves
local spring, clamp01, progress = curves.spring, curves.clamp01, curves.progress
local ease = curves.easing
local sin, cos, pi, min, max, abs = math.sin, math.cos, math.pi, math.min, math.max, math.abs

local Motion = {}

-- The feel of every move, in SwiftUI's spring terms.
local FEEL = {
	move = { response = 0.52, damping = 0.74 }, -- a row travelling to its place
	pop = { response = 0.42, damping = 0.58 }, -- a new component arriving
	land = { response = 0.5, damping = 0.62 }, -- a piece flying in to assemble
	stagger = 0.035, -- between rows in one change
	settle = 1.4, -- after which a change is drawn as its end state
	lift = 0.035, -- how much a travelling row grows
	shadow = { blur = 22, y = 8, opacity = 0.2 },
	fade = 0.22, -- a row's old face giving way to its new one
	leave = 0.38, -- a removed component falling away
}
Motion.FEEL = FEEL

-- ── Pieces ───────────────────────────────────────────────────────────────

local cache = {}
local function load(native, path, density)
	local key = path .. "@" .. density
	cache[key] = cache[key] or native.image(path, density)
	return cache[key]
end

local crops = {}
local function crop(image, rect)
	crops[image] = crops[image] or {}
	local key = rect.x .. "," .. rect.y .. "," .. rect.w .. "," .. rect.h
	local piece = crops[image][key]
	if not piece then
		piece = image:crop(rect.x, rect.y, rect.w, rect.h)
		crops[image][key] = piece
	end
	return piece
end

-- Draws a piece of `image` from `rect` at (x, y), scaled about its centre.
local function piece(pen, image, rect, x, y, scale, alpha, shadow)
	if alpha <= 0.003 then return end
	local canvas = pen.canvas
	pen:save()
	pen:translate(x + rect.w / 2, y + rect.h / 2)
	if scale ~= 1 then pen:scale(scale) end
	if alpha < 1 then pen:fade(alpha) end
	if shadow and shadow > 0.01 then
		pen:save()
		pen:shadow({ dy = FEEL.shadow.y * shadow, blur = FEEL.shadow.blur * shadow, color = { 0, 0, 0, FEEL.shadow.opacity * shadow } })
		pen:fill(Shape.roundedRect(-rect.w / 2 + 2, -rect.h / 2 + 2, rect.w - 4, rect.h - 4, 12), 0xFFFFFF)
		pen:restore()
	end
	canvas:image(crop(image, rect), -rect.w / 2, -rect.h / 2, rect.w, rect.h)
	pen:restore()
end

-- ── The phone: states, morphs, assembly ─────────────────────────────────

local PHONE = { w = 402, h = 874, statics = { status = true, header = true } }

-- A state: its screenshot and its components.
local function state(native, dir, name, rows)
	local image = load(native, dir .. "todo-iphone-" .. name .. ".png", 3)
	return { name = name, image = image, parts = Regions.todo(image, rows) }
end

-- Keys of a state's moving parts, top to bottom.
local function ordered(parts)
	local keys = {}
	for key in pairs(parts) do if not PHONE.statics[key] then table.insert(keys, key) end end
	table.sort(keys, function(a, b) return parts[a].y < parts[b].y end)
	return keys
end

local function still(pen, s)
	pen.canvas:image(s.image, 0, 0, PHONE.w, PHONE.h)
end

-- Whether two crops show the same thing: a few pixels across the middle
-- line of each, compared.
local faces = {}
local function sameFace(imageA, ra, imageB, rb)
	local key = tostring(imageA) .. tostring(imageB) .. ra.x .. ra.y .. rb.x .. rb.y
	if faces[key] ~= nil then return faces[key] end
	local same = true
	for i = 1, 24 do
		local fx, fy = (i % 12) / 12 + 0.03, i <= 12 and 0.35 or 0.62
		local r1, g1, b1 = imageA:pixel(ra.x + ra.w * fx, ra.y + ra.h * fy)
		local r2, g2, b2 = imageB:pixel(rb.x + rb.w * fx, rb.y + rb.h * fy)
		if abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) > 0.12 then same = false; break end
	end
	faces[key] = same
	return same
end

-- A morph from state A to B starting at t0.
local function morph(pen, t, A, B, t0)
	pen:rect(0, 0, PHONE.w, PHONE.h, 0xFFFFFF)
	for key in pairs(PHONE.statics) do
		local r = B.parts[key]
		pen.canvas:image(crop(B.image, r), r.x, r.y, r.w, r.h)
	end
	local keysB, index = ordered(B.parts), {}
	for i, key in ipairs(keysB) do index[key] = i end
	local arriving, travelling = {}, {}
	-- Components leaving fall away first, in their old order.
	for i, key in ipairs(ordered(A.parts)) do
		if not B.parts[key] then
			local r = A.parts[key]
			local u = ease.inCubic(progress(t, t0 + i * FEEL.stagger * 0.5, t0 + i * FEEL.stagger * 0.5 + FEEL.leave))
			piece(pen, A.image, r, r.x, r.y + 60 * u, 1 - 0.12 * u, 1 - u)
		end
	end
	for _, key in ipairs(keysB) do
		if A.parts[key] then table.insert(travelling, key) else table.insert(arriving, key) end
	end
	-- Rows travel, staggered top to bottom, lifted while they move. A row
	-- changes face (a cross-fade) only if its pixels changed; rows that
	-- move are drawn over rows that stay, on an opaque backing, so rows
	-- crossing each other never mix.
	local moving = {}
	for _, key in ipairs(travelling) do
		local ra, rb = A.parts[key], B.parts[key]
		local start = t0 + 0.08 + index[key] * FEEL.stagger
		local k = spring(t - start, FEEL.move.response, FEEL.move.damping)
		local distance = abs(rb.y - ra.y) + abs(rb.x - ra.x)
		local item = { key = key, ra = ra, rb = rb, start = start, k = k, distance = distance,
			lift = distance > 2 and sin(pi * clamp01(k)) or 0, same = sameFace(A.image, ra, B.image, rb) }
		if item.lift > 0.01 then table.insert(moving, item) else table.insert(moving, 1, item) end
	end
	table.sort(moving, function(a, b) return a.lift < b.lift end)
	for _, item in ipairs(moving) do
		local ra, rb, k = item.ra, item.rb, item.k
		local x, y = ra.x + (rb.x - ra.x) * k, ra.y + (rb.y - ra.y) * k
		local change = item.same and 1 or clamp01((t - item.start) / FEEL.fade)
		-- A row that stays put but changes face gives a little bump.
		local bump = (item.distance <= 2 and not item.same) and 0.05 * sin(pi * clamp01((t - item.start) / 0.35)) or 0
		local scale = 1 + FEEL.lift * item.lift + bump
		if item.lift > 0.01 then
			pen:save()
			pen:translate(x + rb.w / 2, y + rb.h / 2)
			pen:scale(scale)
			pen:shadow({ dy = FEEL.shadow.y * item.lift, blur = FEEL.shadow.blur * item.lift,
				color = { 0, 0, 0, FEEL.shadow.opacity * item.lift } })
			pen:fill(Shape.roundedRect(-rb.w / 2, -rb.h / 2, rb.w, rb.h, 10), 0xFFFFFF)
			pen:restore()
		end
		if change < 1 then piece(pen, A.image, ra, x, y, scale, 1 - change) end
		piece(pen, B.image, rb, x, y, scale, change)
	end
	-- New components pop in, after the rows have started to make room.
	for i, key in ipairs(arriving) do
		local r = B.parts[key]
		local start = t0 + 0.18 + (i - 1) * 0.08
		local k = spring(t - start, FEEL.pop.response, FEEL.pop.damping)
		piece(pen, B.image, r, r.x, r.y - 24 * (1 - k), 0.72 + 0.28 * k, clamp01((t - start) / 0.12), 0)
	end
end

-- Assembly: the state's pieces rise and pop into place, groups landing on
-- the given beats.
local function assemble(pen, t, S, beats)
	pen:rect(0, 0, PHONE.w, PHONE.h, 0xFFFFFF)
	local keys = ordered(S.parts)
	table.insert(keys, 1, "header")
	table.insert(keys, 1, "status")
	local seed = 7
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for i, key in ipairs(keys) do
		local r = S.parts[key]
		local group = key == "status" and 1 or (key == "header" and 1 or (key == "progress" and 2
			or (key:match("^task") and r.y < (S.parts.completed and S.parts.completed.y or 1e9)) and 3 or 4))
		local start = beats[group] - 0.12 + (i % 5) * 0.025
		local k = spring(t - start, FEEL.land.response, FEEL.land.damping)
		-- Each piece rises into place from just below it, growing from small
		-- with a slight turn, so nothing crosses the screen's edge.
		local dx, dy = (rnd() - 0.5) * 40 * (1 - k), (50 + rnd() * 40) * (1 - k)
		local turn = (rnd() - 0.5) * 0.35 * (1 - k)
		if t >= start then
			pen:save()
			pen:translate(r.x + r.w / 2 + dx, r.y + r.h / 2 + dy)
			pen:rotate(turn)
			pen:scale(0.5 + 0.5 * k)
			pen:fade(clamp01((t - start) / 0.1))
			pen.canvas:image(crop(S.image, r), -r.w / 2, -r.h / 2, r.w, r.h)
			pen:restore()
		end
	end
end

-- A finger on glass: it arrives, presses, and a ring spreads as it lifts.
local function touch(pen, t, tap)
	local d = t - tap.at
	if d < -0.3 or d > 0.55 then return end
	local arrive = clamp01((d + 0.3) / 0.22)
	local press = d >= 0 and d < 0.16 and 1 - abs(d - 0.08) / 0.08 or 0
	local leave = clamp01((d - 0.18) / 0.25)
	local r = 22 * (1 - 0.18 * press)
	pen:save()
	pen:fade((1 - leave) * arrive)
	pen:shadow({ dy = 2, blur = 10, color = { 0, 0, 0, 0.25 } })
	pen:fill(Shape.circle(tap.x, tap.y + 14 * (1 - arrive), r), rgb(0xFFFFFF, 0.55 + 0.25 * press))
	pen:shadow()
	pen:stroke(Shape.circle(tap.x, tap.y + 14 * (1 - arrive), r), rgb(0x000000, 0.18), 1.5)
	pen:restore()
	if d > 0.02 then
		local u = ease.outCubic(clamp01((d - 0.02) / 0.45))
		pen:stroke(Shape.circle(tap.x, tap.y, 22 + 38 * u), rgb(0x0A84FF, 0.55 * (1 - u)), 3 * (1 - u) + 0.5)
	end
end

-- The chat drawer on the phone: Lua Studio's composer on the iPhone. It
-- rises, listens while the words arrive, sends, shows the answer and
-- sinks. Drawn in the reel: this is the film's device, not a capture.
local DRAWER = { h = 250, radius = 34, inset = 16 }
local TYPE = {
	body = Reel.Pen.style(17, "regular", 0x1D1D1F, -0.01),
	bubble = Reel.Pen.style(17, "medium", 0xFFFFFF, -0.01),
	small = Reel.Pen.style(13, "semibold", 0x8E8E93, 0),
	name = Reel.Pen.style(15, "semibold", 0x1D1D1F, -0.01),
	delta = Reel.Pen.style(13, "semibold", 0x34C759, 0),
	mono = { size = 13, weight = "medium", kern = 0, color = rgb(0x1D1D1F), design = "mono" },
}

local function drawer(pen, t, D)
	local open = spring(t - D.open, 0.5, 0.78)
	local close = t >= D.close and ease.inCubic(clamp01((t - D.close) / 0.32)) or 0
	local rise = open * (1 - close)
	if rise <= 0.002 then return end
	local h = DRAWER.h
	local top = PHONE.h - h * rise
	local w = PHONE.w
	pen:save()
	-- The app dims a little behind the sheet.
	pen:rect(0, 0, w, PHONE.h, rgb(0x000000, 0.12 * rise))
	pen:shadow({ dy = -6, blur = 30, color = { 0, 0, 0, 0.18 } })
	pen:fill(Shape.roundedRect(6, top, w - 12, h + 40, DRAWER.radius), rgb(0xF9F9FB, 0.98))
	pen:shadow()
	pen:fill(Shape.roundedRect(w / 2 - 18, top + 8, 36, 5, 2.5), rgb(0x3C3C43, 0.28))
	local x = DRAWER.inset + 6
	pen:symbol("sparkles", x + 10, top + 34, 18, 0x0A84FF)
	pen:text("Assistant", TYPE.name, x + 26, top + 40, "leading")
	pen:text("on this iPhone", TYPE.small, w - x, top + 40, "trailing")
	-- The spoken request, once sent, as a bubble.
	if t >= D.send then
		local k = spring(t - D.send, 0.42, 0.66)
		local bw = pen:width(D.prompt, TYPE.bubble) + 28
		pen:save()
		pen:translate(w - x - bw / 2, top + 84 + 50 * (1 - k))
		pen:scale(0.8 + 0.2 * k)
		pen:fill(Shape.roundedRect(-bw / 2, -18, bw, 36, 18), 0x0A84FF)
		pen:text(D.prompt, TYPE.bubble, 0, 6, "center")
		pen:restore()
	end
	-- The answer: what changed.
	if t >= D.reply then
		local k = spring(t - D.reply, 0.45, 0.72)
		pen:save()
		pen:fade(clamp01((t - D.reply) / 0.15))
		pen:translate(0, 14 * (1 - k))
		pen:symbol("sparkles", x + 10, top + 134, 14, 0x0A84FF)
		pen:text(D.replyText, TYPE.body, x + 26, top + 140, "leading")
		pen:fill(Shape.roundedRect(x + 26, top + 152, w - 2 * x - 26, 30, 10), rgb(0x767680, 0.12))
		pen:symbol("chevron.left.forwardslash.chevron.right", x + 42, top + 167, 13, 0x0A84FF)
		pen:text(D.file, TYPE.mono, x + 56, top + 172, "leading")
		pen:text(D.delta, TYPE.delta, w - x - 10, top + 172, "trailing")
		pen:restore()
	end
	-- The composer: listening while the words arrive, then empty.
	local cy = top + h - 40
	pen:fill(Shape.roundedRect(x - 4, cy - 22, w - 2 * x + 8, 44, 22), 0xFFFFFF)
	pen:stroke(Shape.roundedRect(x - 4, cy - 22, w - 2 * x + 8, 44, 22), rgb(0x3C3C43, 0.12), 1)
	local listening = t >= D.listen and t < D.send
	local mx = w - x - 22
	pen:fill(Shape.circle(mx, cy, 17), listening and 0xFF3B30 or 0x0A84FF)
	pen:symbol(listening and "waveform" or "arrow.up", mx, cy, 17, 0xFFFFFF)
	if listening then
		local cursor = x + 12
		for i, word in ipairs(D.words) do
			if t >= word[1] then
				local k = spring(t - word[1], 0.3, 0.7)
				pen:save()
				pen:fade(min(1, (t - word[1]) / 0.08))
				pen:translate(0, 8 * (1 - k))
				cursor = cursor + pen:text(word[2], TYPE.body, cursor, cy + 6, "leading") + 5
				pen:restore()
			end
		end
		-- The waveform after the words, following the voice.
		for i = 0, 11 do
			local energy = 0
			for _, word in ipairs(D.words) do
				local dt = t - word[1]
				if dt > -0.05 and dt < 0.4 then energy = max(energy, math.exp(-abs(dt - 0.1) / 0.12)) end
			end
			local bh = 4 + 22 * (0.2 + 0.8 * energy) * (0.4 + 0.6 * abs(sin(t * 19 + i * 1.3)))
			pen:fill(Shape.roundedRect(cursor + 6 + i * 6, cy - bh / 2, 3, bh, 1.5), rgb(0x0A84FF, 0.85))
		end
	elseif t < D.send then
		pen:save()
		pen:fade(0.4)
		pen:text("Describe a change…", TYPE.body, x + 12, cy + 6, "leading")
		pen:restore()
	end
	pen:restore()
end

-- phone(pen, t, spec) draws the phone's screen at t. spec = {dir, rows
-- (Todo.states()), timeline = {{at, state, assemble = beats}, …}, taps =
-- {{at, x, y}…}, drawer = {…}}. Each timeline entry after the first morphs
-- from the previous state at its `at`.
function Motion.phone(pen, t, spec, native)
	spec.states = spec.states or {}
	local function get(name)
		spec.states[name] = spec.states[name] or state(native, spec.dir, name, spec.rows[name])
		return spec.states[name]
	end
	local line = spec.timeline
	local current = 1
	for i, entry in ipairs(line) do if t >= entry.at then current = i end end
	local entry = line[current]
	local S = get(entry.state)
	if current == 1 and entry.assemble and t < entry.assemble[4] + FEEL.settle then
		assemble(pen, t, S, entry.assemble)
	elseif current > 1 and t < entry.at + FEEL.settle then
		morph(pen, t, get(line[current - 1].state), S, entry.at)
	else
		still(pen, S)
	end
	if spec.drawer then drawer(pen, t, spec.drawer) end
	for _, tap in ipairs(spec.taps or {}) do touch(pen, t, tap) end
end

-- Where a component of a state sits, for a tap aimed at it.
function Motion.part(spec, native, stateName, key)
	spec.states = spec.states or {}
	spec.states[stateName] = spec.states[stateName] or state(native, spec.dir, stateName, spec.rows[stateName])
	return spec.states[stateName].parts[key]
end

-- ── Lua Studio on the iPad ──────────────────────────────────────────────

-- The conversation ends above the suggestion chips (which start at y 932).
local STUDIO = { w = 1376, h = 1032, chat = { x = 452, y = 95, w = 924, h = 830 },
	-- The stage's phone preview, which updates with the phone beside it.
	preview = { x = 24, y = 118, w = 392, h = 892 },
	-- The draft in the composer, on the field's glass.
	field = { x = 599, y = 984, right = 770, h = 22, color = 0xFDFDFD, text = 166 } }

-- studio(pen, t, spec, native). spec = {dir, sends = {{at, typeFrom,
-- typeTo}…}, previews = {{at, version}…}}: sends[i] types edit i's prompt
-- and sends it; previews switch the stage's preview to a version.
function Motion.studio(pen, t, spec, native)
	local canvas = pen.canvas
	spec.images = spec.images or {}
	local function image(k)
		spec.images[k] = spec.images[k] or load(native, spec.dir .. "studio-v" .. k .. ".png", 2)
		return spec.images[k]
	end
	spec.chats = spec.chats or {}
	local function chat(k)
		spec.chats[k] = spec.chats[k] or Regions.chat(image(k))
		return spec.chats[k]
	end
	-- How many prompts have been sent.
	local sent = 0
	for i, send in ipairs(spec.sends) do if t >= send.at then sent = i end end
	-- The base: the capture after the latest send (its composer holds the
	-- next prompt), with the stage's preview from the latest preview switch.
	local base = image(sent)
	canvas:image(base, 0, 0, STUDIO.w, STUDIO.h)
	local shown = 0
	for _, p in ipairs(spec.previews) do if t >= p.at then shown = p.version end end
	local P = STUDIO.preview
	if shown ~= sent then
		canvas:image(crop(image(shown), P), P.x, P.y, P.w, P.h)
	end
	for _, p in ipairs(spec.previews) do
		local flash = t >= p.at and math.exp(-(t - p.at) / 0.12) or 0
		if flash > 0.01 then pen:fill(Shape.roundedRect(P.x + 6, P.y + 6, P.w - 12, P.h - 12, 44), rgb(0xFFFFFF, 0.55 * flash)) end
	end
	-- The composer: the next prompt is typed in over its time, hidden before.
	local F = STUDIO.field
	local nextSend = spec.sends[sent + 1]
	local reveal = nextSend and progress(t, nextSend.typeFrom, nextSend.typeTo) or 0
	local left = F.x + F.text * reveal
	if left < F.right then pen:rect(left, F.y, F.right - left, F.h, F.color) end
	-- Until its flight starts, the sent prompt still sits in the composer.
	local last = spec.sends[sent]
	if last and t < last.at + (last.fly or 0) then
		local previous = sent > 1 and image(sent - 1) or image(0)
		canvas:image(crop(previous, { x = F.x, y = F.y, w = F.right - F.x, h = F.h }), F.x, F.y, F.right - F.x, F.h)
	end
	-- The conversation: turns from the latest capture; those the latest
	-- send added animate in.
	pen:rect(STUDIO.chat.x, STUDIO.chat.y, STUDIO.chat.w, STUDIO.chat.h, 0xFFFFFF)
	if sent == 0 then return end
	local C = chat(sent)
	local before = sent > 1 and #chat(sent - 1).turns or 0
	-- The exchange starts when the bubble takes off (spec.fly after the send).
	local at = spec.sends[sent].at + (spec.sends[sent].fly or 0)
	local fresh = 0
	for i, turn in ipairs(C.turns) do
		local r = turn.rect
		if r.y + r.h > STUDIO.chat.y + STUDIO.chat.h then break end
		if i <= before then
			canvas:image(crop(base, r), r.x, r.y, r.w, r.h)
		else
			fresh = fresh + 1
			if turn.kind == "user" then
				-- The prompt flies up from the composer into its bubble.
				local start = at
				local k = spring(t - start, 0.7, 0.82)
				local fromX, fromY = F.x, F.y - 10
				local x, y = fromX + (r.x - fromX) * k, fromY + (r.y - fromY) * k
				if t >= start then piece(pen, base, r, x, y, 0.85 + 0.15 * k, clamp01((t - start) / 0.08), sin(pi * clamp01(k))) end
			elseif turn.kind == "card" then
				local start = at + 0.45
				local k = spring(t - start, FEEL.pop.response, 0.7)
				piece(pen, base, r, r.x, r.y + 30 * (1 - k), 0.94 + 0.06 * k, clamp01((t - start) / 0.12))
				-- The diff lines wipe in, one after another, on the card's grey.
				for j, lineRect in ipairs(t >= start and C.lines or {}) do
					if lineRect.card == r or (lineRect.y > r.y and lineRect.y < r.y + r.h) then
						local lineStart = start + 0.18 + (j - 1) * 0.035
						local u = ease.outCubic(progress(t, lineStart, lineStart + 0.22))
						local y = lineRect.y + 30 * (1 - k)
						if u < 1 then
							pen:rect(lineRect.x + lineRect.w * u, y, lineRect.w * (1 - u) + 2, lineRect.h, rgb(0xF2F2F7))
						end
					end
				end
			else
				local start = at + 0.2 + (fresh - 2) * 0.35
				local k = spring(t - start, 0.45, 0.8)
				piece(pen, base, r, r.x, r.y + 16 * (1 - k), 1, clamp01((t - start) / 0.18))
			end
		end
	end
end

return Motion
