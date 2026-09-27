-- The reel element vocabulary. Each entry may define:
--   define(node, context)  a definition (palette, style); draws nothing
--   setup(node, context)   resolves captures, sprites and styles once
--   position(node)         default x, y in the parent's units
--   anchor(node)           the point inside the node placed at x, y
--   bounds(node)           {x, y, w, h} children see as their area
--   paint(node, rc, t)     draws in the node's own units
local Curves = require("reel.curves")
local Scene = require("reel.scene")

local value = Scene.value
local progress, spring, ease = Curves.progress, Curves.spring, Curves.ease

local Elements = {}

-- Shadow geometry scales with how large the sprite is on screen, so a
-- window lifts the same way whether it fills the frame or sits in a wall.
local SHADOW = { offset = 22, blur = 60, opacity = 0.55, inset = 1, fill = 0.1 }
-- Words rise from behind a mask a little taller than the line.
local RISE = { maskLeft = 0.2, maskTop = 1.05, maskWidth = 0.4, maskHeight = 1.35, travel = 1.15, exitTravel = 1.2,
	response = 1 / 1.9, damping = 0.62, exitStagger = 0.035, exitDuration = 0.28, wordSpace = 0.26 }
local SWEEP = { band = 160, overscan = 400, angle = 0.35, opacity = 0.16 }

local function unpackColor(color, alpha)
	return color[1], color[2], color[3], (color[4] or 1) * (alpha or 1)
end

-- Evenly spaced stops for a list of colours, in the flat form the canvas takes.
local function stops(colors)
	local list = {}
	for i, color in ipairs(colors) do
		local r, g, b, a = unpackColor(color)
		for _, v in ipairs({ r, g, b, a, #colors == 1 and 0 or (i - 1) / (#colors - 1) }) do table.insert(list, v) end
	end
	if #colors == 1 then
		local r, g, b, a = unpackColor(colors[1])
		for _, v in ipairs({ r, g, b, a, 1 }) do table.insert(list, v) end
	end
	return list
end

local function drawSprite(node, rc, sprite, t)
	local canvas, native = rc.canvas, rc.context.native
	local radius = value(node.radius, t) or 0
	local shadow = value(node.shadow, t) or 0
	local w, h = sprite.w, sprite.h
	if shadow > 0 then
		local s = rc.scale
		canvas:save()
		canvas:shadow(0, SHADOW.offset * s * shadow, SHADOW.blur * s * shadow, 0, 0, 0, SHADOW.opacity * math.min(1, shadow))
		canvas:fill(native.path():roundedRect(SHADOW.inset, SHADOW.inset, w - SHADOW.inset * 2, h - SHADOW.inset * 2, math.max(radius, 1)),
			SHADOW.fill, SHADOW.fill, SHADOW.fill, 1)
		canvas:restore()
	end
	canvas:save()
	if radius > 0 then canvas:clip(native.path():roundedRect(0, 0, w, h, radius)) end
	canvas:image(sprite.image, 0, 0, w, h)
	canvas:restore()
end

local function resolveCapture(node, context)
	local name = node.attrs.capture
	if name then
		if not context.captures then node:fail("capture=\"" .. name .. "\" needs captures in the reel data") end
		node.captureRef = context.captures:get(name)
	end
	return node:capture()
end

-- ── Structure ────────────────────────────────────────────────────────────

Elements.Reel = {}
Elements.Group = {}
Elements.Scene = {}

-- <Palette name="brand" colors="#C65BF0 #6E6BFF"/>
Elements.Palette = {
	define = function(node, context)
		local colors = {}
		for hex in (node.attrs.colors or ""):gmatch("#%x+") do table.insert(colors, Scene.parseHex(hex)) end
		if #colors == 0 then node:fail("needs colors") end
		context.palettes[node.attrs.name or node:fail("needs a name")] = colors
	end,
}

-- <Style name="head" size="78" weight="semibold" color="#F5F5F7" tracking="-0.022"/>
-- `gradient` names a palette instead of a colour; `tracking` is in ems.
Elements.Style = {
	define = function(node, context)
		local size = tonumber(node.attrs.size) or node:fail("needs a size")
		context.styles[node.attrs.name or node:fail("needs a name")] = {
			size = size, weight = node.attrs.weight or "regular",
			kern = size * (tonumber(node.attrs.tracking) or 0),
			color = Scene.parseHex(node.attrs.color or "#FFFFFF"), gradient = node.attrs.gradient,
		}
	end,
}

-- ── Captures ─────────────────────────────────────────────────────────────

-- <Frame capture="map-dark"> gives its children the capture's window points,
-- centred on (x, y), without drawing the window.
local function captureCenter(node)
	local w, h = node:capture():size()
	return w / 2, h / 2
end

Elements.Frame = {
	setup = function(node, context)
		if not resolveCapture(node, context) then node:fail("needs a capture") end
	end,
	anchor = captureCenter,
	bounds = function(node) local w, h = node:capture():size(); return { 0, 0, w, h } end,
}

-- <Window capture="map-dark" radius="24" shadow="1"/> draws the whole capture.
Elements.Window = {
	setup = function(node, context)
		if not resolveCapture(node, context) then node:fail("needs a capture") end
		node.radius = node:number("radius", 0)
		node.shadow = node:number("shadow", 0)
	end,
	anchor = captureCenter,
	bounds = Elements.Frame.bounds,
	paint = function(node, rc, t)
		drawSprite(node, rc, node:capture():piece("window"), t)
	end,
}

-- <Piece rect="#treemap/developer" outset="12" key="700, 300"/>: a part of
-- the nearest capture, placed where it was in the window by default.
Elements.Piece = {
	setup = function(node, context)
		if not resolveCapture(node, context) then node:fail("needs a capture") end
		node.radius = node:number("radius", 0)
		node.shadow = node:number("shadow", 0)
		local key = node.attrs.key and { node.attrs.key:match("^%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*$") }
		if key and not key[1] then node:fail("key must be \"x, y\"") end
		node.sprite = function()
			local sprite = node:capture():piece(node.attrs.rect,
				{ outset = tonumber(node.attrs.outset), key = key and { tonumber(key[1]), tonumber(key[2]) } })
			node.sprite = function() return sprite end
			return sprite
		end
	end,
	position = function(node)
		local sprite = node.sprite()
		return sprite.x + sprite.w / 2, sprite.y + sprite.h / 2
	end,
	anchor = function(node)
		local sprite = node.sprite()
		return sprite.w / 2, sprite.h / 2
	end,
	bounds = function(node) local s = node.sprite(); return { 0, 0, s.w, s.h } end,
	paint = function(node, rc, t) drawSprite(node, rc, node.sprite(), t) end,
}

-- <Fill rect="#treemap" color="sample(1000, 820)" outset="1"/>: covers part
-- of a window, in window points; `outset` is in screen pixels.
Elements.Fill = {
	setup = function(node, context)
		resolveCapture(node, context)
		node.fill = node:color("color") or node:fail("needs a color")
		node.outset = node:number("outset", 0)
	end,
	paint = function(node, rc, t)
		local x, y, w, h
		if node.attrs.rect then
			x, y, w, h = node:capture():rect(node.attrs.rect)
		else
			x, y, w, h = table.unpack(rc.bounds)
		end
		local o = value(node.outset, t) / rc.scale
		rc.canvas:fillRect(x - o, y - o, w + o * 2, h + o * 2, unpackColor(value(node.fill, t)))
	end,
}

-- <Sweep at="9.2" duration="0.55"/>: a glint crossing the parent's bounds.
Elements.Sweep = {
	setup = function(node)
		node.at = node:number("at") or node:fail("needs at")
		node.duration = node:number("duration", 0.55)
		node.opacity = node:number("opacity", SWEEP.opacity)
	end,
	paint = function(node, rc, t)
		local at = value(node.at, t)
		local p = progress(t, at, at + value(node.duration, t))
		if p <= 0 or p >= 1 then return end
		local canvas, s = rc.canvas, rc.scale
		local bx, by, bw, bh = table.unpack(rc.bounds)
		local overscan, band = SWEEP.overscan / s, SWEEP.band / s
		local o = value(node.opacity, t)
		canvas:save()
		canvas:clipRect(bx, by, bw, bh)
		canvas:translate(bx - overscan + (bw + overscan * 2) * p, by + bh / 2)
		canvas:rotate(SWEEP.angle)
		canvas:linearGradient({ 1, 1, 1, 0, 0, 1, 1, 1, o, 0.5, 1, 1, 1, 0, 1 }, -band, 0, band, 0)
		canvas:restore()
	end,
}

-- ── Stage ────────────────────────────────────────────────────────────────

-- <Backdrop color="#08080A"> fills the frame; put <Glow>s and a <Vignette>
-- inside it.
Elements.Backdrop = {
	setup = function(node) node.fill = node:color("color", { 0, 0, 0, 1 }) end,
	paint = function(node, rc, t)
		local scene = rc.scene
		rc.canvas:fillRect(0, 0, scene.width, scene.height, unpackColor(value(node.fill, t)))
	end,
}

-- <Glow color="#9B3FE0" radius="760" alpha="0.22"/>: a soft light at (x, y).
Elements.Glow = {
	setup = function(node)
		node.fill = node:color("color", { 1, 1, 1, 1 })
		node.radius = node:number("radius", 500)
	end,
	paint = function(node, rc, t)
		local r, g, b = unpackColor(value(node.fill, t))
		rc.canvas:radialGradient({ r, g, b, 1, 0, r, g, b, 0, 1 }, 0, 0, 0, value(node.radius, t))
	end,
}

-- <Vignette inner="500" outer="1250" alpha="0.55"/>, centred on the frame.
Elements.Vignette = {
	setup = function(node)
		node.inner = node:number("inner", 500)
		node.outer = node:number("outer", 1250)
	end,
	paint = function(node, rc, t)
		local scene = rc.scene
		rc.canvas:radialGradient({ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 }, scene.width / 2, scene.height / 2,
			value(node.inner, t), value(node.outer, t), false, true)
	end,
}

-- ── Type ─────────────────────────────────────────────────────────────────

local function textRun(context, word, style)
	local key = word .. "|" .. style.size .. "|" .. style.weight .. "|" .. style.kern
	local run = context.textCache[key]
	if not run then
		local native = context.native.text(word, style.size, style.weight, style.kern)
		run = { native = native, width = (native:metrics()) }
		context.textCache[key] = run
	end
	return run
end

-- Fills a word, with a gradient spanning the whole line when the style has one.
local function fillWord(canvas, context, run, style, x, spanFrom, spanTo)
	if style.gradient then
		local colors = context.palettes[style.gradient] or error("reel: unknown palette " .. style.gradient, 0)
		canvas:save()
		canvas:clipText(run.native, x, 0)
		canvas:linearGradient(stops(colors), spanFrom, 0, spanTo, 0, true, true)
		canvas:restore()
	else
		canvas:fillText(run.native, x, 0, unpackColor(style.color))
	end
end

-- <Text text="Every byte," style="head" x="960" y="176" align="center"
--       at="8.12" stagger="0.07" exit="9.72"/>
-- Each word rises on a spring from behind its own baseline mask and leaves
-- upward through it. (x, y) is the baseline point the alignment refers to.
Elements.Text = {
	setup = function(node, context)
		local style = context.styles[node.attrs.style or ""]
		if not style then node:fail("unknown style " .. tostring(node.attrs.style)) end
		node.style = style
		node.at = node:number("at", 0)
		node.exit = node:number("exit")
		node.stagger = node:number("stagger", 0.07)
		node.words = {}
		for word in (node.attrs.text or ""):gmatch("%S+") do table.insert(node.words, textRun(context, word, style)) end
		local space = style.size * RISE.wordSpace
		local total = -space
		for _, run in ipairs(node.words) do total = total + run.width + space end
		node.space, node.total = space, math.max(0, total)
		local align = node.attrs.align or "center"
		node.left = align == "leading" and 0 or (align == "trailing" and -node.total or -node.total / 2)
	end,
	paint = function(node, rc, t)
		local canvas, style = rc.canvas, node.style
		local size = style.size
		local at, exit, stagger = value(node.at, t), value(node.exit, t), value(node.stagger, t)
		local cursor, left, total = node.left, node.left, node.total
		for i, run in ipairs(node.words) do
			local begin = at + (i - 1) * stagger
			local out = exit and ease(t, exit + (i - 1) * RISE.exitStagger, exit + (i - 1) * RISE.exitStagger + RISE.exitDuration, "inCubic") or 0
			if t >= begin and out < 1 then
				local p = spring(t - begin, RISE.response, RISE.damping)
				canvas:save()
				canvas:clipRect(cursor - size * RISE.maskLeft, -size * RISE.maskTop, run.width + size * RISE.maskWidth, size * RISE.maskHeight)
				canvas:translate(cursor, (1 - p) * size * RISE.travel - out * size * RISE.exitTravel)
				fillWord(canvas, rc.context, run, style, 0, left - cursor, left - cursor + total)
				canvas:restore()
			end
			cursor = cursor + run.width + node.space
		end
	end,
}

return Elements
