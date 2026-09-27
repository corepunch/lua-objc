-- The reel element vocabulary: thin mappings from attributes to the pen
-- (reel/pen.lua). Each entry may define:
--   define(node, context)     a definition (palette, style); draws nothing
--   setup(node, context)      resolves captures, sprites and styles once
--   update(node, rc, t)       per-frame work before the node is placed
--   position(node)            default x, y in the parent's units
--   anchor(node)              the point inside the node placed at x, y
--   bounds(node)              {x, y, w, h} children see as their area
--   paint(node, rc, t, clip)  draws in the node's own units
--   ownsClip                  the element applies `clip` itself (sprites
--                             keep their shadow outside the clip)
local Curves = require("reel.curves")
local Pen = require("reel.pen")
local Scene = require("reel.scene")

local value = Scene.value
local progress, spring, ease, clamp01 = Curves.progress, Curves.spring, Curves.ease, Curves.clamp01
local Shape = Pen.Shape

local Elements = {}

-- Words rise from behind a mask a little taller than the line.
local RISE = { maskLeft = 0.2, maskTop = 1.05, maskWidth = 0.4, maskHeight = 1.35, travel = 1.15, exitTravel = 1.2,
	response = 1 / 1.9, damping = 0.62, exitStagger = 0.035, exitDuration = 0.28, wordSpace = 0.26 }
-- Slammed words land from 2.4 times their size on a hard spring.
local SLAM = { from = 2.4, response = 1 / 2.6, damping = 0.5, fade = 0.06, pivot = 0.35 }

local function resolveCapture(node, context)
	local name = node.attrs.capture
	if name then
		if not context.captures then node:fail("capture=\"" .. name .. "\" needs captures in the reel data") end
		node.captureRef = context.captures:get(name)
	end
	return node:capture()
end

local function numbers(node, list)
	for name, default in pairs(list) do node[name] = node:number(name, default) end
end

-- ── Structure ────────────────────────────────────────────────────────────

Elements.Reel = {}
Elements.Group = {}
Elements.Scene = {}

-- <Let name="wave" value="outExpo(progress(t, 4, 4.45))"/>: a per-frame
-- variable for the attributes after it (document order).
Elements.Let = {
	setup = function(node, context)
		node.name = node.attrs.name or node:fail("needs a name")
		node.compute = node:value("value") or node:fail("needs a value")
		-- Several scenes may reuse a variable name; none may hide a helper
		-- or the reel data.
		context.lets = context.lets or {}
		if not context.lets[node.name] and context.env[node.name] ~= nil then node:fail("would hide " .. node.name) end
		context.lets[node.name] = true
	end,
	update = function(node, rc, t)
		rawset(rc.context.env, node.name, node.compute(t))
	end,
}

-- <Cue sound="whoosh" at="7.45" until="7.95"/>: a sound event with no picture.
Elements.Cue = {
	setup = function(node)
		local at = tonumber(node.attrs.at) or node:fail("needs a numeric at")
		node:addEvent(at, node.attrs.sound or node:fail("needs a sound"),
			{ ["until"] = tonumber(node.attrs["until"]) and tonumber(node.attrs["until"]) + node.offset or nil })
	end,
}

-- <Draw with="dive"/>: a bespoke shot from the reel data, drawn in the
-- node's units with its transform and motion. A shot is a function
-- `shots.dive(pen, t, node)`, or a table `{ setup = fn(node, context),
-- draw = fn(pen, t, node) }` whose setup runs while the reel loads: it
-- resolves captures and pieces up front, so a missing one fails the load
-- instead of a render minutes in.
Elements.Draw = {
	setup = function(node, context)
		local name = node.attrs.with or node:fail("needs with=\"shot\"")
		local shot = context.shots[name] or node:fail("no shot named " .. name .. " in data.shots")
		resolveCapture(node, context)
		if type(shot) == "table" then
			node.shot = shot.draw or node:fail("shot " .. name .. " needs a draw function")
			if shot.setup then shot.setup(node, context) end
		else
			node.shot = shot
		end
	end,
	paint = function(node, rc, t)
		node.shot(rc.pen, t, node)
	end,
}

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
-- `gradient` names a palette instead of a colour; `tracking` is in ems;
-- `digits="true"` uses monospaced figures.
Elements.Style = {
	define = function(node, context)
		local size = tonumber(node.attrs.size) or node:fail("needs a size")
		local gradient = node.attrs.gradient and (context.palettes[node.attrs.gradient]
			or node:fail("unknown palette " .. node.attrs.gradient))
		context.styles[node.attrs.name or node:fail("needs a name")] = {
			size = size, weight = node.attrs.weight or "regular",
			kern = tonumber(node.attrs.kern) or size * (tonumber(node.attrs.tracking) or 0),
			color = Scene.parseHex(node.attrs.color or "#FFFFFF"), gradient = gradient,
			digits = node.attrs.digits == "true",
		}
	end,
}

local function style(node, context)
	local found = context.styles[node.attrs.style or ""]
	if not found then node:fail("unknown style " .. tostring(node.attrs.style)) end
	return found
end

-- ── Captures ─────────────────────────────────────────────────────────────

local function captureCenter(node)
	local w, h = node:capture():size()
	return w / 2, h / 2
end
local function captureBounds(node)
	local w, h = node:capture():size()
	return { 0, 0, w, h }
end

-- <Frame capture="map-dark"> gives its children the capture's window points,
-- centred on (x, y), without drawing the window.
Elements.Frame = {
	setup = function(node, context)
		if not resolveCapture(node, context) then node:fail("needs a capture") end
	end,
	anchor = captureCenter,
	bounds = captureBounds,
}

local function spriteSetup(node, context)
	if not resolveCapture(node, context) then node:fail("needs a capture") end
	numbers(node, { radius = 0, shadow = 0 })
end

local function paintSprite(node, rc, t, sprite, clip)
	rc.pen:sprite(sprite, { radius = value(node.radius, t), shadow = value(node.shadow, t), clip = clip })
end

-- <Window capture="map-dark" radius="24" shadow="1" downsample="0.3"/>
Elements.Window = {
	ownsClip = true,
	setup = function(node, context)
		spriteSetup(node, context)
		node.downsample = tonumber(node.attrs.downsample)
	end,
	anchor = captureCenter,
	bounds = captureBounds,
	paint = function(node, rc, t, clip)
		paintSprite(node, rc, t, node:capture():piece("window", { downsample = node.downsample }), clip)
	end,
}

-- <Piece rect="#treemap/developer" outset="12" key="700, 300" part="x, y, w, h"/>:
-- a part of the nearest capture, placed where it was in the window by
-- default. `part` narrows the rect to a sub-rectangle of it.
Elements.Piece = {
	ownsClip = true,
	setup = function(node, context)
		spriteSetup(node, context)
		local key = node.attrs.key and { node.attrs.key:match("^%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*$") }
		if key and not key[1] then node:fail("key must be \"x, y\"") end
		local part
		if node.attrs.part then
			part = {}
			for n in node.attrs.part:gmatch("[^,%s]+") do table.insert(part, tonumber(n) or node:fail("bad part")) end
			if #part ~= 4 then node:fail("part must be \"x, y, w, h\"") end
		end
		-- Resolve the rect now so a missing view fails the load; the pixels
		-- are cut on first use.
		node:capture():rect(node.attrs.rect)
		node.sprite = function()
			local sprite = node:capture():piece(node.attrs.rect,
				{ outset = tonumber(node.attrs.outset), key = key and { tonumber(key[1]), tonumber(key[2]) }, part = part })
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
	paint = function(node, rc, t, clip) paintSprite(node, rc, t, node.sprite(), clip) end,
}

-- <Fill rect="#treemap" color="sample(1000, 820)" outset="1"/>: covers part
-- of a window, in window points; `outset` is in screen pixels.
Elements.Fill = {
	setup = function(node, context)
		resolveCapture(node, context)
		if node.attrs.rect then
			if not node:capture() then node:fail("rect=\"" .. node.attrs.rect .. "\" needs a capture") end
			node:capture():rect(node.attrs.rect)
		end
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
		local o = value(node.outset, t) / rc.pen.zoom
		rc.pen:rect(x - o, y - o, w + o * 2, h + o * 2, value(node.fill, t))
	end,
}

-- <Sweep at="9.2" duration="0.55"/>: a glint crossing the parent's bounds.
Elements.Sweep = {
	setup = function(node)
		node.at = node:number("at") or node:fail("needs at")
		numbers(node, { duration = 0.55, opacity = 0.16 })
	end,
	paint = function(node, rc, t)
		local at = value(node.at, t)
		rc.pen:sweep(rc.bounds, progress(t, at, at + value(node.duration, t)), { opacity = value(node.opacity, t) })
	end,
}

-- ── Shapes ───────────────────────────────────────────────────────────────

-- <Rect x y width height radius color shadow="blur" shadowY shadowColor/>
-- and <Circle x y radius color stroke="width"/>, drawn at their position.
Elements.Rect = {
	setup = function(node)
		numbers(node, { width = 0, height = 0, radius = 0, shadowBlur = 0, shadowY = 0 })
		node.fill = node:color("color", { 1, 1, 1, 1 })
		node.shadowColor = node:color("shadowColor", { 0, 0, 0, 0.5 })
		node.centered = node.attrs.origin == "center"
	end,
	paint = function(node, rc, t)
		local w, h, r = value(node.width, t), value(node.height, t), value(node.radius, t)
		local x, y = node.centered and -w / 2 or 0, node.centered and -h / 2 or 0
		local pen, blur = rc.pen, value(node.shadowBlur, t)
		if blur > 0 then pen:save(); pen:shadow({ dy = value(node.shadowY, t), blur = blur, color = value(node.shadowColor, t) }) end
		pen:fill(r > 0 and Shape.roundedRect(x, y, w, h, r) or Shape.rect(x, y, w, h), value(node.fill, t))
		if blur > 0 then pen:restore() end
	end,
}

Elements.Circle = {
	setup = function(node)
		numbers(node, { radius = 10, stroke = 0, shadowBlur = 0, shadowY = 0 })
		node.fill = node:color("color", { 1, 1, 1, 1 })
		node.shadowColor = node:color("shadowColor", { 0, 0, 0, 0.5 })
	end,
	paint = function(node, rc, t)
		local pen, r, width, blur = rc.pen, value(node.radius, t), value(node.stroke, t), value(node.shadowBlur, t)
		if r <= 0 then return end
		if blur > 0 then pen:save(); pen:shadow({ dy = value(node.shadowY, t), blur = blur, color = value(node.shadowColor, t) }) end
		if width > 0 then pen:stroke(Shape.circle(0, 0, r), value(node.fill, t), width)
		else pen:fill(Shape.circle(0, 0, r), value(node.fill, t)) end
		if blur > 0 then pen:restore() end
	end,
}

-- <Symbol name="checkmark.circle.fill" size="22" color="#34C759"/> and
-- <Chip symbol="hammer.fill" color="#1C7CF4" size="104"/>, centred on (x, y).
Elements.Symbol = {
	setup = function(node)
		node.name = node.attrs.name or node:fail("needs a name")
		node.size = node:number("size", 24)
		node.fill = node:color("color", { 1, 1, 1, 1 })
	end,
	paint = function(node, rc, t) rc.pen:symbol(node.name, 0, 0, value(node.size, t), value(node.fill, t)) end,
}

Elements.Chip = {
	setup = function(node)
		node.symbol = node.attrs.symbol or node:fail("needs a symbol")
		node.size = node:number("size", 64)
		node.fill = node:color("color", { 0, 0.48, 1, 1 })
	end,
	paint = function(node, rc, t) rc.pen:chip(node.symbol, value(node.fill, t), 0, 0, value(node.size, t)) end,
}

-- <Ring radius width sweep turn segments="logo" track="#1C1C1E"/>: a
-- segmented donut centred on (x, y); `segments` names a data list of
-- {share, colour} pairs.
Elements.Ring = {
	setup = function(node, context)
		numbers(node, { radius = 100, width = 20, sweep = 1, turn = 0 })
		node.segments = context.data[node.attrs.segments or ""] or node:fail("needs segments from the reel data")
		node.track = node:color("track", Pen.rgb(0x1C1C1E))
	end,
	paint = function(node, rc, t)
		rc.pen:ring({ cx = 0, cy = 0, r = value(node.radius, t), width = value(node.width, t), sweep = value(node.sweep, t),
			rotation = value(node.turn, t), segments = node.segments, track = value(node.track, t) })
	end,
}

-- <Burst at x y colors="#34C759 #FFFFFF" count speed seed/>
Elements.Burst = {
	setup = function(node)
		node.burst = { at = tonumber(node.attrs.at) or node:fail("needs a numeric at"), x = 0, y = 0,
			count = tonumber(node.attrs.count) or 100, speed = tonumber(node.attrs.speed) or 1500,
			seed = tonumber(node.attrs.seed) or 1, colors = {} }
		for hex in (node.attrs.colors or "#FFFFFF"):gmatch("#%x+") do table.insert(node.burst.colors, Scene.parseHex(hex)) end
	end,
	paint = function(node, rc, t) rc.pen:burst(node.burst, t) end,
}

-- <Glow color radius/>, <Backdrop color/>, <Vignette inner outer/>
Elements.Backdrop = {
	setup = function(node) node.fill = node:color("color", { 0, 0, 0, 1 }) end,
	paint = function(node, rc, t)
		local scene = rc.scene
		rc.pen:rect(0, 0, scene.width, scene.height, value(node.fill, t))
	end,
}

-- A multi-stop glow: colors="{rgb(0x8E44E8, a), rgb(0x2F6BFF, a * 0.4), rgb(0, 0)}"
-- (an expression) with locations="0, 0.45, 1".
Elements.Glow = {
	setup = function(node)
		node.fill = node:color("color", { 1, 1, 1, 1 })
		node.radius = node:number("radius", 500)
		node.colors = node:value("colors")
		if node.attrs.locations then
			node.locations = {}
			for n in node.attrs.locations:gmatch("[^,%s]+") do table.insert(node.locations, tonumber(n)) end
		end
	end,
	paint = function(node, rc, t)
		if node.colors then
			rc.pen:radial(0, 0, 0, value(node.radius, t), node.colors(t), node.locations)
		else
			rc.pen:glow(0, 0, value(node.radius, t), value(node.fill, t))
		end
	end,
}

Elements.Vignette = {
	setup = function(node) numbers(node, { inner = 500, outer = 1250 }) end,
	paint = function(node, rc, t)
		local scene = rc.scene
		rc.pen:radial(scene.width / 2, scene.height / 2, value(node.inner, t), value(node.outer, t),
			{ { 0, 0, 0, 0 }, { 0, 0, 0, 1 } }, nil, true)
	end,
}

-- ── Type ─────────────────────────────────────────────────────────────────

local function layoutWords(node, context)
	local st = node.style
	local pen = Pen.new(nil, context.native, context)
	node.words = {}
	for word in (node.attrs.text or ""):gmatch("%S+") do table.insert(node.words, pen:run(word, st)) end
	node.space = st.size * RISE.wordSpace
	local total = -node.space
	for _, run in ipairs(node.words) do total = total + run.width + node.space end
	node.total = math.max(0, total)
	local align = node.attrs.align or "center"
	node.left = align == "leading" and 0 or (align == "trailing" and -node.total or -node.total / 2)
end

-- <Text text style x y align at stagger exit sound/>: words rise on a spring
-- from behind their own baseline mask and leave upward through it. (x, y)
-- is the baseline point the alignment refers to. A gradient spans the line.
Elements.Text = {
	setup = function(node, context)
		node.style = style(node, context)
		node.at = tonumber(node.attrs.at) or 0
		node.exit = tonumber(node.attrs.exit)
		node.stagger = tonumber(node.attrs.stagger) or 0.07
		layoutWords(node, context)
		if node.attrs.sound then node:addEvent(node.at, node.attrs.sound) end
	end,
	paint = function(node, rc, t)
		local pen, st = rc.pen, node.style
		local size = st.size
		local at, exit, stagger = node.at, node.exit, node.stagger
		local cursor, left, total = node.left, node.left, node.total
		for i, run in ipairs(node.words) do
			local begin = at + (i - 1) * stagger
			local out = exit and ease(t, exit + (i - 1) * RISE.exitStagger, exit + (i - 1) * RISE.exitStagger + RISE.exitDuration, "inCubic") or 0
			if t >= begin and out < 1 then
				local p = spring(t - begin, RISE.response, RISE.damping)
				pen.canvas:save()
				pen.canvas:clipRect(cursor - size * RISE.maskLeft, -size * RISE.maskTop, run.width + size * RISE.maskWidth, size * RISE.maskHeight)
				pen:word(run, st, cursor, (1 - p) * size * RISE.travel - out * size * RISE.exitTravel, left - cursor, left - cursor + total)
				pen.canvas:restore()
			end
			cursor = cursor + run.width + node.space
		end
	end,
}

-- <Slam text style x y at="0.5, 1, 1.5" gradient="word|line"/>: each word
-- lands from large on its own hit (a slam sound each). A gradient style
-- spans each word by default.
Elements.Slam = {
	setup = function(node, context)
		node.style = style(node, context)
		layoutWords(node, context)
		node.hits = {}
		for hit in (node.attrs.at or ""):gmatch("[^,%s]+") do table.insert(node.hits, tonumber(hit) or node:fail("bad hit " .. hit)) end
		if #node.hits ~= #node.words then node:fail("needs one hit per word") end
		node.styles = {}
		for i, entry in ipairs(node.words) do
			node.styles[i] = node.style
			if node.attrs["style" .. i] then node.styles[i] = context.styles[node.attrs["style" .. i]] or node:fail("unknown style" .. i) end
		end
		for _, hit in ipairs(node.hits) do node:addEvent(hit, node.attrs.sound or "slam") end
	end,
	paint = function(node, rc, t)
		local pen, size = rc.pen, node.style.size
		local x = node.left
		for i, run in ipairs(node.words) do
			local start = node.hits[i]
			if t >= start then
				local p = spring(t - start, SLAM.response, SLAM.damping)
				local s = SLAM.from + (1 - SLAM.from) * p
				pen:save()
				pen:fade(clamp01((t - start) / SLAM.fade))
				pen:translate(x + run.width / 2, -size * SLAM.pivot)
				pen:scale(s)
				pen:translate(-run.width / 2, size * SLAM.pivot)
				pen:word(run, node.styles[i], 0, 0)
				pen:restore()
			end
			x = x + run.width + node.space
		end
	end,
}

-- <Counter value="19.8 * outQuart(…)" format="%.1f" final="19.8" unit=" GB"
-- style/>: digits tick in fixed slots right-aligned to the final value's
-- width, and the unit holds still. The gradient spans the whole reading.
Elements.Counter = {
	setup = function(node, context)
		node.style = style(node, context)
		node.reading = node:number("value", 0)
		node.format = node.attrs.format or "%.0f"
		node.final = tonumber(node.attrs.final) or 0
		node.unit = node.attrs.unit or ""
		node.unitStyle = node.attrs.unitStyle and context.styles[node.attrs.unitStyle] or node.style
	end,
	paint = function(node, rc, t)
		local pen = rc.pen
		local digits = pen:run(string.format(node.format, value(node.reading, t)), node.style)
		local final = pen:run(string.format(node.format, node.final), node.style)
		local unit = pen:run(node.unit, node.unitStyle)
		local total = final.width + unit.width
		local left = -total / 2
		pen:word(digits, node.style, left + final.width - digits.width, 0, digits.width - final.width, digits.width - final.width + total)
		pen:word(unit, node.unitStyle, left + final.width, 0, -final.width, unit.width)
	end,
}

return Elements
