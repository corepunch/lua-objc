-- The reel scene graph: etlua renders XML once, this builds nodes from it,
-- and every frame draws the nodes as a function of time.
--
-- Nodes nest like views. Each has a position (x, y) in its parent's units,
-- an anchor inside itself, a scale (sx, sy stretch it), a rotation, an
-- opacity and an optional clip; children draw in the node's own units. A
-- <Window> therefore gives its children window points, and a piece cut from
-- that window lands where it was on the page.
--
-- Attribute values are numbers, colours ("#RRGGBB", "#RRGGBBAA") or Lua
-- expressions of `t` evaluated per frame ("520 + 180 * sin(t * 0.35)").
-- `motion` holds modifiers from reel/motion.lua, built once. `stagger="1/8"`
-- runs each child that much later than the one before, so repeated nodes
-- can share one motion.
local Curves = require("reel.curves")
local Motion = require("reel.motion")
local Pen = require("reel.pen")
local Space = require("reel.space")

local Scene = {}

local Node = {}
Node.__index = Node

local function fail(node, message)
	error(string.format("reel: <%s> %s", node.tag, message), 0)
end

-- ── Expression environment ───────────────────────────────────────────────

local function baseEnvironment(data, grid)
	local env = {
		sin = math.sin, cos = math.cos, abs = math.abs, min = math.min, max = math.max,
		floor = math.floor, sqrt = math.sqrt, exp = math.exp, log = math.log, pi = math.pi,
		hypot = function(x, y) return math.sqrt(x * x + y * y) end,
		beat = grid.beat, bar = grid.bar, grid = grid, rgb = Pen.rgb,
		-- 1 when x is positive, else 0: attributes cannot contain ">".
		step = function(x) return x > 0 and 1 or 0 end,
		shakeX = function(t, hits, amount) return (Curves.shake(t, hits, amount)) end,
		shakeY = function(t, hits, amount) return select(2, Curves.shake(t, hits, amount)) end,
	}
	for name, fn in pairs(Curves) do if type(fn) == "function" then env[name] = fn end end
	for name, fn in pairs(Curves.easing) do env[name] = fn end
	for name, fn in pairs(Motion) do env[name] = fn end
	for name, fn in pairs(Pen.Shape) do env[name] = fn end
	for name, fn in pairs(Space) do env[name] = fn end
	return setmetatable(env, { __index = data })
end
Scene.baseEnvironment = baseEnvironment

-- ── Attribute compilation ────────────────────────────────────────────────

local function parseHex(value)
	local hex = value:match("^#(%x+)$")
	if not hex or (#hex ~= 6 and #hex ~= 8) then return nil end
	local n = function(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
	return { n(1), n(3), n(5), #hex == 8 and n(7) or 1 }
end
Scene.parseHex = parseHex

local function compileExpression(node, name, source, env)
	local chunk, err = load("return function(t) return " .. source .. " end", "=" .. node.tag .. "." .. name, "t", env)
	if not chunk then fail(node, name .. ": " .. err) end
	return chunk()
end
Scene.compileExpression = compileExpression

-- A number or a function of t.
local function numberAttribute(node, name, env, default)
	local source = node.attrs[name]
	if source == nil or source == "" then return default end
	local value = tonumber(source)
	if value then return value end
	return compileExpression(node, name, source, env)
end

-- A colour table {r, g, b, a} or a function of t returning one.
local function colorAttribute(node, name, env, default)
	local source = node.attrs[name]
	if source == nil or source == "" then return default end
	local color = parseHex(source)
	if color then return color end
	return compileExpression(node, name, source, env)
end

-- Any value (shape, table, string) as a function of t.
local function valueAttribute(node, name, env)
	local source = node.attrs[name]
	if source == nil or source == "" then return nil end
	return compileExpression(node, name, source, env)
end

local function value(v, t)
	if type(v) == "function" then return v(t) end
	return v
end
Scene.value = value

local function pair(node, name)
	local source = node.attrs[name]
	if not source then return nil end
	local a, b = source:match("^%s*([%d.%-]+)%s*,%s*([%d.%-]+)%s*$")
	if not a then fail(node, name .. " must be \"x, y\"") end
	return { tonumber(a), tonumber(b) }
end

-- ── Nodes ────────────────────────────────────────────────────────────────

function Node:addEvent(time, kind, extra)
	local e = { time = time + self.offset, kind = kind, tag = self.tag, id = self.attrs.id }
	for key, v in pairs(extra or {}) do e[key] = v end
	table.insert(self.context.events, e)
end

-- build(element, context, parent, offset) -> node, or nil for definitions.
local function build(element, context, parent, offset)
	local tag = element.tag
	local def = context.elements[tag]
	if not def then error("reel: unknown element <" .. tag .. ">", 0) end
	local node = setmetatable({ tag = tag, attrs = element.attrs, element = element, def = def, parent = parent,
		children = {}, context = context, offset = offset }, Node)
	-- Capture-aware helpers resolve against the nearest capture, so a colour
	-- sampled in a <Window> reads that window's pixels.
	local env = setmetatable({
		sample = function(x, y)
			local capture = node:capture()
			if not capture then fail(node, "sample() needs a capture") end
			local r, g, b = capture:sample(x, y)
			return { r, g, b, 1 }
		end,
	}, { __index = context.env })
	node.env = env
	if def.define then
		def.define(node, context)
		return nil
	end
	node.from = numberAttribute(node, "from", env)
	node.to = numberAttribute(node, "to", env)
	node.x = numberAttribute(node, "x", env)
	node.y = numberAttribute(node, "y", env)
	node.scale = numberAttribute(node, "scale", env, 1)
	node.sx = numberAttribute(node, "sx", env, 1)
	node.sy = numberAttribute(node, "sy", env, 1)
	node.rotation = numberAttribute(node, "rotation", env, 0)
	node.alpha = numberAttribute(node, "alpha", env, 1)
	node.clip = valueAttribute(node, "clip", env)
	node.anchorPoint = pair(node, "anchor")
	node.anchorX = numberAttribute(node, "anchorX", env)
	node.anchorY = numberAttribute(node, "anchorY", env)
	if element.attrs.capture then
		if not context.captures then fail(node, "capture=\"" .. element.attrs.capture .. "\" needs captures in the reel data") end
		node.captureRef = context.captures:get(element.attrs.capture)
	end
	node.resolution = tonumber(node.attrs.resolution)
	node.stagger = numberAttribute(node, "stagger", env)
	if type(node.stagger) == "function" then node.stagger = node.stagger(0) end
	node.motions = {}
	local motion = node.attrs.motion
	if motion and motion ~= "" then
		local chunk, err = load("return " .. motion, "=" .. tag .. ".motion", "t", env)
		if not chunk then fail(node, "motion: " .. err) end
		local ok, result = pcall(function() return table.pack(chunk()) end)
		if not ok then fail(node, "motion: " .. tostring(result)) end
		for i = 1, result.n do
			if type(result[i]) ~= "table" or not result[i].apply then fail(node, "motion item " .. i .. " is not a modifier") end
			table.insert(node.motions, result[i])
		end
	end
	if def.setup then def.setup(node, context) end
	for _, m in ipairs(node.motions) do
		for _, e in ipairs(m.events) do node:addEvent(e.time, e.kind) end
	end
	-- An element that builds its own children (a <SceneView>'s records)
	-- says children = false.
	if def.children == false then return node end
	local index = 0
	for _, child in ipairs(element.children or {}) do
		if child.kind == "element" then
			local childOffset = offset + (node.stagger or 0) * index
			local built = build(child, context, node, childOffset)
			if built then
				built.delay = (node.stagger or 0) * index
				table.insert(node.children, built)
				index = index + 1
			end
		end
	end
	return node
end

-- buildNode(element, context, parent, offset): for elements that build
-- some of their children themselves (a <SceneView> building a <Surface>).
Scene.buildNode = build

function Node:capture()
	local node = self
	while node do
		if node.captureRef then return node.captureRef end
		node = node.parent
	end
	return nil
end

function Node:number(name, default) return numberAttribute(self, name, self.env, default) end
function Node:color(name, default) return colorAttribute(self, name, self.env, default) end
function Node:value(name) return valueAttribute(self, name, self.env) end
function Node:fail(message) fail(self, message) end

-- The per-frame transform state that modifiers work on.
local state = { dx = 0, dy = 0, scale = 1, sx = 1, sy = 1, rotation = 0, alpha = 1 }

local ALPHA_EPSILON = 0.004
local SCALE_EPSILON = 0.0005

-- Soft, full-frame layers (lights, gradients) cost the same to rasterise at
-- any detail; `resolution="0.25"` draws such a subtree offscreen at that
-- fraction of the frame and scales it up. Only for nodes in frame units.
function Node:drawReduced(rc, t)
	local scene, factor = rc.scene, self.resolution
	if not self.layer then
		local w, h = math.max(1, math.ceil(scene.width * factor)), math.max(1, math.ceil(scene.height * factor))
		self.layer = rc.context.native.canvas(w, h)
		self.layerPen = Pen.new(self.layer, rc.context.native, rc.context)
	end
	local layer, outer = self.layer, rc.pen
	layer:clear(0, 0, 0, 0)
	layer:save()
	layer:scale(factor)
	rc.pen = self.layerPen
	self.resolution = nil
	local ok, err = pcall(self.draw, self, rc, t)
	self.resolution = factor
	rc.pen = outer
	layer:restore()
	if not ok then error(err, 0) end
	outer.canvas:image(layer:snapshot(), 0, 0, scene.width, scene.height)
end

function Node:draw(rc, t)
	if self.resolution then return self:drawReduced(rc, t) end
	t = t - (self.delay or 0)
	if self.from and t < value(self.from, t) then return end
	if self.to and t >= value(self.to, t) then return end
	local def = self.def
	if def.update then def.update(self, rc, t) end
	state.dx, state.dy, state.sx, state.sy = 0, 0, value(self.sx, t), value(self.sy, t)
	state.rotation, state.scale, state.alpha = value(self.rotation, t), value(self.scale, t), value(self.alpha, t)
	for _, m in ipairs(self.motions) do
		m.apply(state, t)
		if state.alpha <= ALPHA_EPSILON then return end
	end
	local pen = rc.pen
	local scale, sx, sy, rotation, dx, dy, alpha = state.scale, state.sx, state.sy, state.rotation, state.dx, state.dy, state.alpha
	if pen.opacity * alpha <= ALPHA_EPSILON or math.abs(scale * sx) < SCALE_EPSILON or math.abs(scale * sy) < SCALE_EPSILON then return end
	local x, y = value(self.x, t), value(self.y, t)
	if x == nil or y == nil then
		local px, py = 0, 0
		if def.position then px, py = def.position(self) end
		x, y = x or px, y or py
	end
	local ax, ay = 0, 0
	if self.anchorPoint then
		ax, ay = self.anchorPoint[1], self.anchorPoint[2]
	elseif def.anchor then
		ax, ay = def.anchor(self)
	end
	if self.anchorX then ax = value(self.anchorX, t) end
	if self.anchorY then ay = value(self.anchorY, t) end
	pen:save()
	pen:translate(x + dx, y + dy)
	pen:rotate(rotation)
	pen:scale(scale * sx, scale * sy)
	if ax ~= 0 or ay ~= 0 then pen:translate(-ax, -ay) end
	if alpha ~= 1 then pen:fade(alpha) end
	local outerBounds = rc.bounds
	if def.bounds then rc.bounds = def.bounds(self) end
	local clip = self.clip and self.clip(t)
	if clip and not def.ownsClip then pen:clip(clip) end
	if def.paint then def.paint(self, rc, t, clip) end
	for _, child in ipairs(self.children) do child:draw(rc, t) end
	rc.bounds = outerBounds
	pen:restore()
end

-- ── Scene ────────────────────────────────────────────────────────────────

-- Scene.build(nodes, options) where options = {elements, data, native}.
function Scene.build(nodes, options)
	local root
	for _, node in ipairs(nodes) do
		if node.kind == "element" then root = node; break end
	end
	if not root or root.tag ~= "Reel" then error("reel: the template must have a <Reel> root", 0) end
	local attrs = root.attrs
	local grid = Curves.grid(tonumber(attrs.bpm) or 120)
	local data = options.data or {}
	local context = {
		elements = options.elements, native = options.native, data = data, shots = data.shots or {},
		captures = data.captures, styles = {}, palettes = {}, events = {}, grid = grid, textCache = {},
	}
	context.env = baseEnvironment(data, grid)
	local scene = {
		width = tonumber(attrs.width) or 1920, height = tonumber(attrs.height) or 1080,
		fps = tonumber(attrs.fps) or 30, duration = tonumber(attrs.duration) or 0,
		subframes = tonumber(attrs.subframes) or 5, shutter = tonumber(attrs.shutter) or 0.5,
		background = parseHex(attrs.background or "#000000"), grid = grid, context = context,
	}
	context.scene = scene
	-- Sub-frames may follow the picture: more where the motion is fast.
	if attrs.subframes and not tonumber(attrs.subframes) then
		scene.subframes = compileExpression({ tag = "Reel" }, "subframes", attrs.subframes, context.env)
	end
	scene.root = build(root, context, nil, 0)
	table.sort(context.events, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		return a.kind < b.kind
	end)
	scene.events = context.events
	return scene
end

-- Draws the scene at time t onto a canvas the scene's size.
function Scene.draw(scene, canvas, t)
	local bg = scene.background
	canvas:clear(bg[1], bg[2], bg[3], bg[4])
	scene.pen = scene.pen and scene.pen.canvas == canvas and scene.pen or Pen.new(canvas, scene.context.native, scene.context)
	local pen = scene.pen
	pen.opacity, pen.zoom, pen.stack = 1, 1, nil
	canvas:alpha(1)
	local rc = { pen = pen, scene = scene, context = scene.context, bounds = { 0, 0, scene.width, scene.height } }
	scene.root:draw(rc, t)
end

return Scene
