-- The drawing toolkit shared by every element and by bespoke shots.
--
-- A pen wraps a canvas and tracks the opacity and on-screen scale of the
-- current transform, so shadows, glints and hairlines keep their screen size
-- inside scaled groups. Elements are thin attribute-to-pen mappings; a
-- <Draw with="shot"> node hands the same pen to a Lua function for shots
-- the vocabulary does not cover.
--
--   pen:place({x = 960, y = 540, scale = 2, rotation = 0.1, alpha = 0.5}, function()
--   	pen:sprite(sprite, {radius = 24, shadow = 1, clip = Shape.circle(192, 192, 80)})
--   end)
local Pen = {}
Pen.__index = Pen

local Shape = {}
Pen.Shape = Shape

local sin, cos, exp, pi, abs, max, min, floor, log = math.sin, math.cos, math.exp, math.pi, math.abs, math.max, math.min, math.floor, math.log

-- Pen.new(canvas, native, context)
function Pen.new(canvas, native, context)
	return setmetatable({ canvas = canvas, native = native, context = context or {}, opacity = 1, zoom = 1,
		textCache = (context and context.textCache) or {} }, Pen)
end

-- ── Colours ──────────────────────────────────────────────────────────────

-- rgb(0xC65BF0), rgb(0xC65BF0, 0.5), rgb("#C65BF0"), rgb(r, g, b, a) or a
-- colour table; returns {r, g, b, a}.
function Pen.rgb(value, a, b, alpha)
	if type(value) == "table" then
		if a then return { value[1], value[2], value[3], (value[4] or 1) * a } end
		return value
	end
	if type(value) == "string" then
		local hex = value:match("^#(%x+)$") or error("bad colour " .. value, 2)
		local n = function(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { n(1), n(3), n(5), (#hex == 8 and n(7) or 1) * (a or 1) }
	end
	if b then return { value, a, b, alpha or 1 } end
	return { ((value >> 16) & 0xff) / 255, ((value >> 8) & 0xff) / 255, (value & 0xff) / 255, a or 1 }
end
local rgb = Pen.rgb

local function unpackColor(color, alpha)
	return color[1], color[2], color[3], (color[4] or 1) * (alpha or 1)
end

-- Flat gradient stops from colours, evenly spaced or at `locations`.
function Pen.stops(colors, locations)
	local list = {}
	local count = #colors
	for i, color in ipairs(colors) do
		local r, g, b, a = unpackColor(rgb(color))
		local location = locations and locations[i] or (count == 1 and 0 or (i - 1) / (count - 1))
		for _, v in ipairs({ r, g, b, a, location }) do table.insert(list, v) end
	end
	if count == 1 then
		local r, g, b, a = unpackColor(rgb(colors[1]))
		for _, v in ipairs({ r, g, b, a, 1 }) do table.insert(list, v) end
	end
	return list
end

-- ── Shapes ───────────────────────────────────────────────────────────────
-- Shapes are plain descriptions, built into native paths when used, so an
-- attribute expression can return one: clip="sector(192, 192, 56, 98, -pi/2, sweep)".

function Shape.rect(x, y, w, h) return { kind = "rect", x, y, w, h } end
function Shape.roundedRect(x, y, w, h, r) return { kind = "roundedRect", x, y, w, h, r } end
function Shape.circle(cx, cy, r) return { kind = "ellipse", cx - r, cy - r, r * 2, r * 2 } end
function Shape.ellipse(x, y, w, h) return { kind = "ellipse", x, y, w, h } end
-- An annular sector: radii r0…r1, from `from` radians clockwise by `sweep`.
function Shape.sector(cx, cy, r0, r1, from, sweep) return { kind = "sector", cx, cy, r0, r1, from, sweep } end
-- `shape` with `hole` cut out (even-odd).
function Shape.except(shape, hole) return { kind = "except", shape, hole } end
-- Everything but `hole`, within a large bound.
function Shape.without(hole) return Shape.except(Shape.rect(-1e5, -1e5, 2e5, 2e5), hole) end

local function addShape(path, shape)
	local kind = shape.kind
	if kind == "rect" then
		path:rect(shape[1], shape[2], shape[3], shape[4])
	elseif kind == "roundedRect" then
		path:roundedRect(shape[1], shape[2], shape[3], shape[4], shape[5])
	elseif kind == "ellipse" then
		path:ellipse(shape[1], shape[2], shape[3], shape[4])
	elseif kind == "sector" then
		local cx, cy, r0, r1, from, sweep = table.unpack(shape)
		path:arc(cx, cy, r1, from, from + sweep, false)
		path:arc(cx, cy, r0, from + sweep, from, true)
		path:close()
	elseif kind == "except" then
		addShape(path, shape[1])
		addShape(path, shape[2])
	else
		error("unknown shape " .. tostring(kind), 3)
	end
end

function Pen:path(shape)
	local path = self.native.path()
	addShape(path, shape)
	return path, shape.kind == "except"
end

-- ── State ────────────────────────────────────────────────────────────────

function Pen:save() self.canvas:save(); self.stack = { self.opacity, self.zoom, self.stack } end
function Pen:restore()
	self.canvas:restore()
	self.opacity, self.zoom, self.stack = self.stack[1], self.stack[2], self.stack[3]
end
function Pen:translate(x, y) self.canvas:translate(x, y) end
function Pen:rotate(a) if a ~= 0 then self.canvas:rotate(a) end end
function Pen:scale(sx, sy)
	sy = sy or sx
	self.canvas:scale(sx, sy)
	self.zoom = self.zoom * max(abs(sx), abs(sy))
end
-- Multiplies the opacity of what follows.
function Pen:fade(alpha)
	self.opacity = self.opacity * alpha
	self.canvas:alpha(self.opacity)
end

-- place(options, fn): x, y, scale, sx, sy, rotation, alpha, anchor = {x, y}
-- (the point of the content placed at x, y). Draws nothing when invisible.
function Pen:place(o, fn)
	local alpha = o.alpha or 1
	local s = o.scale or 1
	local sx, sy = s * (o.sx or 1), s * (o.sy or 1)
	if alpha <= 0.004 or abs(sx) < 0.0005 or abs(sy) < 0.0005 then return end
	self:save()
	self:translate(o.x or 0, o.y or 0)
	self:rotate(o.rotation or 0)
	self:scale(sx, sy)
	local anchor = o.anchor
	if anchor then self:translate(-anchor[1], -anchor[2]) end
	if alpha ~= 1 then self:fade(alpha) end
	fn(self)
	self:restore()
end

function Pen:clip(shape)
	local path, evenOdd = self:path(shape)
	self.canvas:clip(path, evenOdd)
end

-- ── Fills ────────────────────────────────────────────────────────────────

function Pen:fill(shape, color, alpha)
	local path, evenOdd = self:path(shape)
	local r, g, b, a = unpackColor(rgb(color), alpha)
	self.canvas:fill(path, r, g, b, a, evenOdd)
end

-- stroke(shape, color, width): `width` in the current units.
function Pen:stroke(shape, color, width, alpha)
	local r, g, b, a = unpackColor(rgb(color), alpha)
	self.canvas:stroke(self:path(shape), width, r, g, b, a)
end

function Pen:rect(x, y, w, h, color, alpha)
	self.canvas:fillRect(x, y, w, h, unpackColor(rgb(color), alpha))
end

-- shadow{dx, dy, blur, color} in screen pixels, applied to what follows
-- until restore; shadow() removes it.
function Pen:shadow(o)
	if not o then self.canvas:shadow(); return end
	local r, g, b, a = unpackColor(rgb(o.color or { 0, 0, 0, 0.5 }))
	self.canvas:shadow(o.dx or 0, o.dy or 0, o.blur or 0, r, g, b, a)
end

-- glow(x, y, radius, color, alpha): a soft light fading to nothing.
function Pen:glow(x, y, radius, color, alpha)
	local r, g, b = unpackColor(rgb(color))
	self.canvas:radialGradient({ r, g, b, alpha or 1, 0, r, g, b, 0, 1 }, x, y, 0, radius)
end

-- radial(x, y, r0, r1, colors, locations, extend)
function Pen:radial(x, y, r0, r1, colors, locations, extendAfter)
	self.canvas:radialGradient(Pen.stops(colors, locations), x, y, r0, r1, false, extendAfter)
end

-- linear(x0, y0, x1, y1, colors, locations): fills the current clip.
function Pen:linear(x0, y0, x1, y1, colors, locations)
	self.canvas:linearGradient(Pen.stops(colors, locations), x0, y0, x1, y1, true, true)
end

-- ── Sprites ──────────────────────────────────────────────────────────────

-- Shadow geometry scales with how large the sprite is on screen, so a
-- window lifts the same way whether it fills the frame or sits in a wall.
local SHADOW = { offset = 22, blur = 60, opacity = 0.55, inset = 1, fill = 0.1 }
Pen.SHADOW = SHADOW

-- sprite(sprite, {radius, shadow, clip}): draws a capture piece at (0, 0) in
-- its own points. The shadow follows the rounded rect, not the clip.
function Pen:sprite(sprite, o)
	o = o or {}
	local canvas = self.canvas
	local w, h = sprite.w, sprite.h
	local radius, shadow = o.radius or 0, o.shadow or 0
	if shadow > 0 then
		local s = self.zoom
		canvas:save()
		canvas:shadow(0, SHADOW.offset * s * shadow, SHADOW.blur * s * shadow, 0, 0, 0, SHADOW.opacity * min(1, shadow))
		canvas:fill(self.native.path():roundedRect(SHADOW.inset, SHADOW.inset, w - SHADOW.inset * 2, h - SHADOW.inset * 2, max(radius, 1)),
			SHADOW.fill, SHADOW.fill, SHADOW.fill, 1)
		canvas:restore()
	end
	canvas:save()
	if radius > 0 then canvas:clip(self.native.path():roundedRect(0, 0, w, h, radius)) end
	if o.clip then self:clip(o.clip) end
	canvas:image(sprite.image, 0, 0, w, h)
	canvas:restore()
end

-- ── Type ─────────────────────────────────────────────────────────────────

-- A text style: {size, weight, kern, color | gradient = {colours}, digits}.
function Pen.style(size, weight, fill, tracking)
	local style = { size = size, weight = weight or "bold", kern = size * (tracking or -0.022) }
	if type(fill) == "table" and type(fill[1]) ~= "number" then style.gradient = fill else style.color = fill and rgb(fill) or rgb(0xF5F5F7) end
	return style
end

-- run(text, style) -> {native, width} (cached).
function Pen:run(text, style)
	local key = text .. "|" .. style.size .. "|" .. style.weight .. "|" .. (style.kern or 0) .. (style.digits and "|d" or "")
	local run = self.textCache[key]
	if not run then
		local native = self.native.text(text, style.size, style.weight, style.kern or 0, style.digits)
		run = { native = native, width = (native:metrics()) }
		self.textCache[key] = run
	end
	return run
end

function Pen:width(text, style)
	return self:run(text, style).width
end

-- word(run, style, x, baseline, spanFrom, spanTo): fills one run; a gradient
-- spans [spanFrom, spanTo] (relative to x), the word itself by default.
function Pen:word(run, style, x, baseline, spanFrom, spanTo)
	local canvas = self.canvas
	if style.gradient then
		canvas:save()
		canvas:clipText(run.native, x, baseline)
		canvas:linearGradient(Pen.stops(style.gradient), x + (spanFrom or 0), 0, x + (spanTo or run.width), 0, true, true)
		canvas:restore()
	else
		canvas:fillText(run.native, x, baseline, unpackColor(style.color))
	end
end

-- text(text, style, x, baseline, align): align is "leading", "center" or
-- "trailing"; returns the drawn width.
function Pen:text(text, style, x, baseline, align)
	local run = self:run(text, style)
	local left = align == "center" and x - run.width / 2 or (align == "trailing" and x - run.width or x)
	self:word(run, style, left, baseline)
	return run.width
end

-- ── Symbols ──────────────────────────────────────────────────────────────

-- symbol(name, cx, cy, height, color, alpha) -> width
function Pen:symbol(name, cx, cy, size, color, alpha)
	if size < 1 or (alpha or 1) <= 0.01 then return 0 end
	return self.canvas:symbol(name, cx, cy, size, unpackColor(rgb(color), alpha))
end

local CHIP = { corner = 0.23, shadowOffset = 0.12, shadowBlur = 0.35, shadowOpacity = 0.45, glyph = 0.6, maxGlyph = 0.66 }

-- chip(name, color, cx, cy, size, alpha, rotation): a rounded square in
-- `color` holding a white symbol, like a category badge.
function Pen:chip(name, color, cx, cy, size, alpha, rotation)
	alpha = alpha or 1
	if alpha <= 0.01 or size <= 1 then return end
	local canvas = self.canvas
	self:save()
	self:fade(alpha)
	self:translate(cx, cy)
	self:rotate(rotation or 0)
	canvas:shadow(0, size * CHIP.shadowOffset, size * CHIP.shadowBlur, 0, 0, 0, CHIP.shadowOpacity)
	self:fill(Shape.roundedRect(-size / 2, -size / 2, size, size, size * CHIP.corner), color)
	canvas:shadow()
	local glyph = size * CHIP.glyph
	self:symbol(name, 0, 0, glyph, 0xFFFFFF)
	self:restore()
end

-- ── Charts and effects ───────────────────────────────────────────────────

-- ring{cx, cy, r, width, sweep, rotation, segments = {{share, colour}…},
-- track, gap}: a segmented donut drawn on from 12 o'clock; `sweep` 0…1.
function Pen:ring(o)
	if (o.alpha or 1) <= 0.002 or o.width <= 0.1 then return end
	self:save()
	if o.alpha then self:fade(o.alpha) end
	local canvas = self.canvas
	local cx, cy, r, width = o.cx, o.cy, o.r, o.width
	self:stroke(Shape.circle(cx, cy, r), o.track or 0x1C1C1E, width)
	local gap = (o.gap or 2.2) * pi / 180
	local angle = -pi / 2 + (o.rotation or 0)
	local limit = angle + (o.sweep or 1) * 2 * pi
	for _, segment in ipairs(o.segments) do
		local span = segment[1] / 100 * 2 * pi
		local finish = min(angle + span - gap, limit)
		if finish > angle then
			local path = self.native.path():arc(cx, cy, r, angle, finish, false)
			local cr, cg, cb, ca = unpackColor(rgb(segment[2]))
			canvas:stroke(path, width, cr, cg, cb, ca)
		end
		angle = angle + span
	end
	self:restore()
end

-- burst{at, x, y, colors, count, speed, seed}: particles thrown from a point
-- with drag and a little gravity, fading over about a second.
function Pen:burst(o, t)
	local dt = t - o.at
	if dt < 0 or dt >= 1.6 then return end
	local seed = o.seed or 1
	local function rnd()
		seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
		return seed / 4294967295
	end
	local drag, colors = 3.2, o.colors
	for i = 0, (o.count or 100) - 1 do
		local angle, v, size, life = rnd() * 2 * pi, o.speed * (0.35 + rnd() * 0.9), 3 + rnd() * 7, 0.7 + rnd() * 0.8
		local dist = v * (1 - exp(-drag * dt)) / drag
		local x, y = o.x + cos(angle) * dist, o.y + sin(angle) * dist + 140 * dt * dt
		local a = min(1, max(0, 1 - dt / life))
		if a > 0 then
			local color = rgb(colors[i % #colors + 1])
			local r = size * (0.5 + 0.5 * a)
			if i % 3 == 0 then
				self.canvas:fillRect(x - r, y - r * 0.35, r * 2, r * 0.7, color[1], color[2], color[3], a)
			else
				self:fill(Shape.ellipse(x - r / 2, y - r / 2, r, r), color, a)
			end
		end
	end
end

-- sweep(rect, p, {band, overscan, angle, opacity}): a glint crossing `rect`
-- ({x, y, w, h}) as p goes 0…1; sizes in screen pixels.
function Pen:sweep(rect, p, o)
	if p <= 0 or p >= 1 then return end
	o = o or {}
	local s = self.zoom
	local band, overscan = (o.band or 160) / s, (o.overscan or 400) / s
	local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
	local canvas = self.canvas
	canvas:save()
	canvas:clipRect(x, y, w, h)
	canvas:translate(x - overscan + (w + overscan * 2) * p, y + h / 2)
	canvas:rotate(o.angle or 0.35)
	local a = o.opacity or 0.16
	canvas:linearGradient({ 1, 1, 1, 0, 0, 1, 1, 1, a, 0.5, 1, 1, 1, 0, 1 }, -band, 0, band, 0)
	canvas:restore()
end

return Pen
