-- The reel scene graph: etlua renders XML once, this builds nodes from it,
-- and every frame draws the nodes as a function of time.
--
-- Nodes nest like views. Each has a position (x, y) in its parent's units,
-- an anchor inside itself, a scale, a rotation and an opacity; children draw
-- in the node's own units. A <Window> therefore gives its children window
-- points, and a piece cut from that window lands where it was on the page
-- without any coordinate mapping in the storyboard.
--
-- Attribute values are numbers, colours ("#RRGGBB", "#RRGGBBAA") or Lua
-- expressions of `t` evaluated per frame ("520 + 180 * sin(t * 0.35)").
-- `motion` holds modifiers from reel/motion.lua, built once.
local Curves = require("reel.curves")
local Motion = require("reel.motion")

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
		clamp01 = Curves.clamp01, progress = Curves.progress, mix = Curves.mix,
		mixScale = Curves.mixScale, ease = Curves.ease, spring = Curves.spring,
		pulse = Curves.pulse, beat = grid.beat, bar = grid.bar, grid = grid,
	}
	for name, fn in pairs(Motion) do env[name] = fn end
	return setmetatable(env, { __index = data })
end

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

local function collectEvents(node, events)
	for _, m in ipairs(node.motions) do
		for _, e in ipairs(m.events) do
			table.insert(events, { time = e.time, kind = e.kind, tag = node.tag, id = node.attrs.id })
		end
	end
end

-- build(element, context, parent) -> node, or nil for definitions.
local function build(element, context, parent)
	local tag = element.tag
	local def = context.elements[tag]
	if not def then error("reel: unknown element <" .. tag .. ">", 0) end
	local node = setmetatable({ tag = tag, attrs = element.attrs, def = def, parent = parent, children = {} }, Node)
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
	node.rotation = numberAttribute(node, "rotation", env, 0)
	node.alpha = numberAttribute(node, "alpha", env, 1)
	node.anchorPoint = pair(node, "anchor")
	node.resolution = tonumber(node.attrs.resolution)
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
	collectEvents(node, context.events)
	for _, child in ipairs(element.children or {}) do
		if child.kind == "element" then
			local built = build(child, context, node)
			if built then table.insert(node.children, built) end
		elseif def.text then
			node.body = (node.body or "") .. child.value
		end
	end
	return node
end

function Node:capture()
	local node = self
	while node do
		if node.captureRef then return node.captureRef end
		node = node.parent
	end
	return nil
end

function Node:number(name, default)
	return numberAttribute(self, name, self.env, default)
end

function Node:color(name, default)
	return colorAttribute(self, name, self.env, default)
end

function Node:fail(message)
	fail(self, message)
end

-- The per-frame transform state that modifiers work on.
local state = { dx = 0, dy = 0, scale = 1, sx = 1, rotation = 0, alpha = 1 }

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
		self.layerSize = { w, h }
	end
	local layer = self.layer
	layer:clear(0, 0, 0, 0)
	layer:save()
	layer:scale(factor)
	local canvas, alpha = rc.canvas, rc.alpha
	rc.canvas, rc.alpha = layer, 1
	self.resolution = nil
	local ok, err = pcall(self.draw, self, rc, t)
	self.resolution = factor
	rc.canvas, rc.alpha = canvas, alpha
	layer:restore()
	if not ok then error(err, 0) end
	canvas:save()
	canvas:alpha(alpha)
	canvas:image(layer:snapshot(), 0, 0, scene.width, scene.height)
	canvas:restore()
end

function Node:draw(rc, t)
	if self.resolution then return self:drawReduced(rc, t) end
	if self.from and t < value(self.from, t) then return end
	if self.to and t >= value(self.to, t) then return end
	local def = self.def
	state.dx, state.dy, state.sx, state.rotation = 0, 0, 1, value(self.rotation, t)
	state.scale, state.alpha = value(self.scale, t), value(self.alpha, t)
	for _, m in ipairs(self.motions) do
		m.apply(state, t)
		if state.alpha <= ALPHA_EPSILON then return end
	end
	local alpha = rc.alpha * state.alpha
	if alpha <= ALPHA_EPSILON or math.abs(state.scale) < SCALE_EPSILON or math.abs(state.sx) < SCALE_EPSILON then return end
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
	local canvas = rc.canvas
	local scale, sx, rotation, dx, dy = state.scale, state.sx, state.rotation, state.dx, state.dy
	canvas:save()
	canvas:translate(x + dx, y + dy)
	if rotation ~= 0 then canvas:rotate(rotation) end
	canvas:scale(scale * sx, scale)
	if ax ~= 0 or ay ~= 0 then canvas:translate(-ax, -ay) end
	canvas:alpha(alpha)
	local outerAlpha, outerScale, outerBounds = rc.alpha, rc.scale, rc.bounds
	rc.alpha, rc.scale = alpha, rc.scale * math.abs(scale)
	if def.bounds then rc.bounds = def.bounds(self) end
	if def.paint then def.paint(self, rc, t) end
	for _, child in ipairs(self.children) do child:draw(rc, t) end
	rc.alpha, rc.scale, rc.bounds = outerAlpha, outerScale, outerBounds
	canvas:restore()
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
	local context = {
		elements = options.elements, native = options.native, data = options.data or {},
		captures = (options.data or {}).captures, styles = {}, palettes = {}, events = {}, grid = grid,
		textCache = {},
	}
	context.env = baseEnvironment(context.data, grid)
	local scene = {
		width = tonumber(attrs.width) or 1920, height = tonumber(attrs.height) or 1080,
		fps = tonumber(attrs.fps) or 30, duration = tonumber(attrs.duration) or 0,
		subframes = tonumber(attrs.subframes) or 5, shutter = tonumber(attrs.shutter) or 0.5,
		background = parseHex(attrs.background or "#000000"), grid = grid, context = context,
	}
	scene.root = build(root, context, nil)
	table.sort(context.events, function(a, b) return a.time < b.time end)
	scene.events = context.events
	return scene
end

-- Draws the scene at time t onto a canvas the scene's size.
function Scene.draw(scene, canvas, t)
	local bg = scene.background
	canvas:clear(bg[1], bg[2], bg[3], bg[4])
	local rc = { canvas = canvas, alpha = 1, scale = 1, scene = scene, context = scene.context,
		bounds = { 0, 0, scene.width, scene.height } }
	scene.root:draw(rc, t)
end

return Scene
