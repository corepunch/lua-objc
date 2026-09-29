-- <SceneView>: SceneKit inside a reel, rendered offline from `t` alone.
--
-- The element speaks the live SceneView's vocabulary (src/appkit/
-- scene_view.m): <Node>, <Camera> and <Light> records with position,
-- rotation (degrees), scale, model, geometry, spin, bob, transition and the
-- rest, so an app's own scene templates, a game's prefabs for instance,
-- render in a reel unchanged. What the live view does on the display clock
-- is a function of time here:
--
--   - every attribute may be a Lua expression of `t`, like any reel
--     attribute: position="path(t, cameraKeys)", rotation="0, 30 * t, 0";
--   - `spin` and `bob` turn and float the content from `t`;
--   - `transition` plays at the record's `from` (insertion) and `to`
--     (removal) with the live view's curves;
--   - `states="…"` is the live view's `nodeStates`: an expression returning
--     poses {id, x, y, z, yaw, pitch, roll, scale, opacity, hidden} that
--     override the template for this frame, which is how a game's own
--     simulation drives its nodes in a reel.
--
-- Reel-only records and attributes extend it for product shots: `slab`
-- geometry (a rounded device body), physically based materials (metalness,
-- roughness, clearcoat, emission), camera lenses (depth of field, bloom),
-- `image` (a capture or piece shown on a node) and <Surface>: a node's
-- screen drawn by ordinary reel elements every frame, so a device shows
-- live, animated app content that stays attached to its glass. A surface
-- may itself hold a <SceneView>: a game running on a phone's screen.
--
-- The view renders at its on-screen pixel size and is placed like a <Rect>:
-- (x, y) is its top-left corner, `width` and `height` its size in the
-- parent's units (the reel's size by default). Where nothing is drawn and
-- there is no `background`, the reel's own stage shows through.
local Curves = require("reel.curves")
local Scene = require("reel.scene")

local World = {}

local rad, sin, max, min, floor = math.rad, math.sin, math.max, math.min, math.floor

-- The live SceneView's transition and idle-motion timing
-- (kSceneTransition* and kSceneBobPeriod in src/main.m).
local TRANSITION = { duration = 0.3, popScale = 1.6, rise = 1.0, overshoot = 1.70158 }
local BOB_PERIOD = 1.6
-- Renders never exceed this many pixels on a side.
local MAX_PIXELS = 4096

local ATTRIBUTES = {
	common = { "id", "position", "rotation", "scale", "hidden", "opacity", "lookAt", "roll", "from", "to" },
	Node = { "model", "geometry", "width", "height", "length", "radius", "chamfer", "cornerRadius", "pipe",
		"reflectivity", "reflectionFalloff", "color", "emission", "metalness", "roughness", "clearcoat",
		"clearcoatRoughness", "lighting", "doubleSided", "transparency", "order", "writesDepth", "readsDepth", "blend",
		"castsShadow", "spin", "bob", "bobPeriod", "transition", "image", "imageSlot" },
	Camera = { "fieldOfView", "fieldOfViewAxis", "zNear", "zFar", "focusDistance", "fStop", "bloom", "bloomThreshold",
		"exposure", "vignetting", "hdr" },
	Light = { "type", "intensity", "color", "temperature", "castsShadow", "shadowRadius", "shadowOpacity",
		"shadowMapSize", "shadowScale", "shadowSamples", "spotInner", "spotOuter" },
}
local VECTORS = { position = true, rotation = true, scale = true, lookAt = true, spin = true }
local COLORS = { color = true, emission = true }
local STRINGS = { id = true, model = true, geometry = true, lighting = true, blend = true, transition = true,
	fieldOfViewAxis = true, type = true, imageSlot = true }
local BOOLEANS = { hidden = true, castsShadow = true, doubleSided = true, writesDepth = true, readsDepth = true, hdr = true }
local GEOMETRY = { "width", "height", "length", "radius", "chamfer", "cornerRadius", "pipe", "reflectivity", "reflectionFalloff" }
local MATERIAL = { "color", "emission", "metalness", "roughness", "clearcoat", "clearcoatRoughness", "lighting",
	"doubleSided", "transparency", "order", "writesDepth", "readsDepth", "blend" }
local LENS = { "fieldOfView", "fieldOfViewAxis", "zNear", "zFar", "focusDistance", "fStop", "bloom", "bloomThreshold",
	"exposure", "vignetting", "hdr" }
local LIGHT = { "type", "intensity", "color", "temperature", "castsShadow", "shadowRadius", "shadowOpacity",
	"shadowMapSize", "shadowScale", "shadowSamples", "spotInner", "spotOuter" }
-- Root attributes the live view uses that have no meaning offline.
local APP_ONLY = { onKey = true, onFrame = true, showsStatistics = true }

local function allowed(tag)
	local set = {}
	for _, name in ipairs(ATTRIBUTES.common) do set[name] = true end
	for _, name in ipairs(ATTRIBUTES[tag]) do set[name] = true end
	return set
end
local ALLOWED = { Node = allowed("Node"), Camera = allowed("Camera"), Light = allowed("Light") }

-- ── Attribute values ─────────────────────────────────────────────────────

local function fail(record, message)
	error(string.format("reel: <%s%s> %s", record.tag, record.attrs.id and (" id=\"" .. record.attrs.id .. "\"") or "", message), 0)
end

local function parseVector(source)
	local parts = {}
	for n in source:gmatch("[^%s,]+") do
		local value = tonumber(n)
		if not value then return nil end
		table.insert(parts, value)
	end
	if #parts == 1 then return { parts[1], parts[1], parts[1] } end
	if #parts == 3 then return parts end
	return nil
end

local function toVector(record, name, v)
	local kind = type(v)
	if kind == "table" then return v end
	if kind == "number" then return { v, v, v } end
	if kind == "string" then return parseVector(v) or fail(record, name .. " must be \"x y z\"") end
	fail(record, name .. " evaluated to " .. kind)
end

local function toColor(record, name, v)
	if type(v) == "table" then return v end
	if type(v) == "string" then return Scene.parseHex(v) or fail(record, name .. " must be #RRGGBB or #RRGGBBAA") end
	fail(record, name .. " evaluated to " .. type(v))
end

-- Compiles one attribute into a constant or a function of t whose result is
-- already converted to its kind.
local function compile(record, name, env)
	local source = record.attrs[name]
	if STRINGS[name] then return source end
	if BOOLEANS[name] and (source == "true" or source == "false") then return source == "true" end
	if name == "spin" then
		-- One number spins about the vertical axis, as in the live view.
		local constant = tonumber(source)
		if constant then return { 0, constant, 0 } end
		constant = parseVector(source)
		if constant then return constant end
		local fn = Scene.compileExpression(record, name, source, env)
		return function(t)
			local v = fn(t)
			if type(v) == "number" then return { 0, v, 0 } end
			return toVector(record, name, v)
		end
	end
	if VECTORS[name] then
		local constant = parseVector(source)
		if constant then return constant end
		local fn = Scene.compileExpression(record, name, source, env)
		return function(t) return toVector(record, name, fn(t)) end
	end
	if COLORS[name] then
		local constant = Scene.parseHex(source)
		if constant then return constant end
		local fn = Scene.compileExpression(record, name, source, env)
		return function(t) return toColor(record, name, fn(t)) end
	end
	local number = tonumber(source)
	if number then return number end
	return Scene.compileExpression(record, name, source, env)
end

local function get(record, name, t, default)
	local v = record.values[name]
	if v == nil then return default end
	if type(v) == "function" then v = v(t) end
	if v == nil then return default end
	return v
end

-- A table of the named attributes at t, and a key that changes when any does.
local function snapshot(record, names, t)
	local out, key = {}, {}
	for _, name in ipairs(names) do
		local v = get(record, name, t)
		out[name] = v
		if type(v) == "table" then v = table.concat(v, ",") end
		table.insert(key, tostring(v))
	end
	return out, table.concat(key, "|")
end

-- ── Records ──────────────────────────────────────────────────────────────

local function isDynamic(record, names)
	for _, name in ipairs(names) do
		if type(record.values[name]) == "function" then return true end
	end
	return false
end

local function applyGeometry(view, record, t)
	local params, key = snapshot(record, GEOMETRY, t)
	if key == record.geometryKey then return end
	record.geometryKey = key
	local ok, err = view.native:geometry(record.handle, record.values.geometry, params)
	if not ok then fail(record, err) end
end

local function applyMaterial(view, record, t)
	local params, key = snapshot(record, MATERIAL, t)
	if key == record.materialKey then return end
	record.materialKey = key
	view.native:material(record.handle, params)
end

local function applyLens(view, record, t)
	local params, key = snapshot(record, LENS, t)
	if key == record.lensKey then return end
	record.lensKey = key
	params.axis = params.fieldOfViewAxis
	view.native:camera(record.handle, params)
end

local function applyLight(view, record, t)
	local params, key = snapshot(record, LIGHT, t)
	if key == record.lightKey then return end
	record.lightKey = key
	view.native:light(record.handle, params)
end

local buildRecords

local function buildRecord(view, element, parent, context)
	local tag = element.tag
	local record = { tag = tag, attrs = element.attrs, values = {}, children = {}, parent = parent }
	local permitted = ALLOWED[tag]
	for name in pairs(element.attrs) do
		if not permitted[name] then fail(record, "has no attribute " .. name) end
		record.values[name] = compile(record, name, view.node.env)
	end
	record.handle = view.native:node(parent and parent.handle or 0)
	table.insert(view.records, record)
	local id = element.attrs.id
	if id then
		if view.byId[id] then fail(record, "repeats id " .. id) end
		view.byId[id] = record
	end
	if tag == "Node" then
		local model, geometry = record.values.model, record.values.geometry
		if model then
			local ok, err = view.native:model(record.handle, model)
			if not ok then fail(record, err) end
		elseif geometry then
			applyGeometry(view, record, 0)
			applyMaterial(view, record, 0)
			record.liveGeometry = isDynamic(record, GEOMETRY)
			record.liveMaterial = isDynamic(record, MATERIAL)
		end
		view.native:shadows(record.handle, get(record, "castsShadow", 0, true))
		if record.values.image then
			if not geometry then fail(record, "image needs a geometry to show it on") end
			record.liveImage = true
		end
	elseif tag == "Camera" then
		applyLens(view, record, 0)
		record.liveLens = isDynamic(record, LENS)
		view.cameras = view.cameras or {}
		table.insert(view.cameras, record)
	elseif tag == "Light" then
		applyLight(view, record, 0)
		record.liveLight = isDynamic(record, LIGHT)
	end
	buildRecords(view, element, record, context)
	return record
end

function buildRecords(view, element, parent, context)
	for _, child in ipairs(element.children or {}) do
		if child.kind == "element" then
			if child.tag == "Surface" then
				if not parent or parent.tag ~= "Node" or not parent.values.geometry then
					error("reel: <Surface> belongs inside a <Node> with a geometry", 0)
				end
				if parent.surface then fail(parent, "has more than one <Surface>") end
				context.buildingSurface = true
				parent.surface = Scene.buildNode(child, context, view.node, view.node.offset)
				context.buildingSurface = nil
			elseif ALLOWED[child.tag] then
				table.insert(parent and parent.children or view.roots, buildRecord(view, child, parent, context))
			else
				error("reel: <" .. child.tag .. "> is not a scene record (Node, Camera, Light or Surface)", 0)
			end
		end
	end
end

-- ── Per-frame posing ─────────────────────────────────────────────────────

local function easeOutBack(u)
	local s = TRANSITION.overshoot
	u = u - 1
	return u * u * ((s + 1) * u + s) + 1
end

-- SceneKit's ease-in-ease-out and ease-out timing curves.
local function easeInOut(u) return u * u * (3 - 2 * u) end
local function easeOut(u) return 1 - (1 - u) * (1 - u) end

-- Scale, lift and opacity factors of a record's transitions at t, or nil
-- when it is not on stage.
local function transition(record, t)
	local from, to = get(record, "from", t), get(record, "to", t)
	local kind = record.values.transition
	local d = TRANSITION.duration
	local scale, lift, opacity = 1, 0, 1
	if from and t < from then return nil end
	if to and t >= to + (kind and d or 0) then return nil end
	if kind and from and t < from + d then
		local u = (t - from) / d
		if kind == "pop" then scale = easeOutBack(u)
		elseif kind == "rise" then
			local e = easeOut(u)
			lift, opacity = -TRANSITION.rise * (1 - e), e
		elseif kind == "fade" then opacity = u end
	end
	if kind and to and t >= to then
		local u = (t - to) / d
		if kind == "pop" then scale, opacity = scale * (1 + (TRANSITION.popScale - 1) * u), opacity * (1 - u)
		elseif kind == "rise" then lift, opacity = lift + TRANSITION.rise * u, opacity * (1 - u)
		elseif kind == "fade" then opacity = opacity * (1 - u) end
	end
	return scale, lift, opacity
end

local ZERO, ONE = { 0, 0, 0 }, { 1, 1, 1 }

local function pose(view, record, t, states, visibleParent)
	local native, handle = view.native, record.handle
	local scale, lift, fade = transition(record, t)
	local hidden = not scale or get(record, "hidden", t, false)
	local p, r, s = get(record, "position", t, ZERO), get(record, "rotation", t, ZERO), get(record, "scale", t, ONE)
	local x, y, z = p[1], p[2] + (lift or 0), p[3]
	local pitch, yaw, roll = r[1], r[2], r[3]
	local sx, sy, sz = s[1] * (scale or 1), s[2] * (scale or 1), s[3] * (scale or 1)
	local opacity = get(record, "opacity", t, 1) * (fade or 1)
	local state = record.attrs.id and states[record.attrs.id]
	if state then
		x, y, z = state.x or x, state.y or y, state.z or z
		pitch, yaw, roll = state.pitch or pitch, state.yaw or yaw, state.roll or roll
		if state.scale then sx, sy, sz = state.scale, state.scale, state.scale end
		opacity = state.opacity or opacity
		if state.hidden ~= nil then hidden = state.hidden end
	end
	native:pose(handle, x, y, z, rad(pitch), rad(yaw), rad(roll), sx, sy, sz, opacity, hidden)
	local target = get(record, "lookAt", t)
	if target then native:aim(handle, target[1], target[2], target[3], rad(get(record, "roll", t, 0))) end
	record.visible = visibleParent and not hidden and opacity > 0.002
	if record.tag == "Node" then
		local spin, bob = get(record, "spin", t), get(record, "bob", t, 0)
		if spin or bob ~= 0 then
			spin = spin or ZERO
			local offset = 0
			if bob ~= 0 then
				local period = get(record, "bobPeriod", t, BOB_PERIOD)
				local phase = (t % period) / period
				offset = bob * easeInOut(phase < 0.5 and phase * 2 or 2 - phase * 2)
			end
			native:inner(handle, offset, rad(spin[1] * t), rad(spin[2] * t), rad(spin[3] * t))
		end
		if record.liveGeometry then applyGeometry(view, record, t) end
		if record.liveMaterial then applyMaterial(view, record, t) end
		if record.liveImage and record.visible then
			local image = get(record, "image", t)
			if type(image) == "table" then image = image.image end
			native:texture(handle, image, record.values.imageSlot or "emission")
		end
	elseif record.tag == "Camera" and record.liveLens then
		applyLens(view, record, t)
	elseif record.tag == "Light" and record.liveLight then
		applyLight(view, record, t)
	end
	for _, child in ipairs(record.children) do pose(view, child, t, states, record.visible) end
end

-- Draws a node's <Surface> into its own canvas and shows it on the node.
local function paintSurface(view, record, rc, t)
	local surface = record.surface
	local w, h = surface.width, surface.height
	local density = surface.density
	if not surface.canvas then
		surface.canvas = rc.context.native.canvas(max(1, floor(w * density + 0.5)), max(1, floor(h * density + 0.5)))
		surface.pen = require("reel.pen").new(surface.canvas, rc.context.native, rc.context)
	end
	local canvas, pen = surface.canvas, surface.pen
	local bg = surface.fill
	canvas:clear(bg[1], bg[2], bg[3], bg[4])
	canvas:save()
	canvas:scale(density, density)
	canvas:alpha(1)
	pen.opacity, pen.zoom, pen.stack = 1, density, nil
	local inner = { pen = pen, scene = { width = w, height = h, context = rc.context }, context = rc.context, bounds = { 0, 0, w, h } }
	surface:draw(inner, t)
	canvas:restore()
	view.native:texture(record.handle, canvas:snapshot(), surface.slot)
end

-- ── Elements ─────────────────────────────────────────────────────────────

World.SceneView = {
	children = false,
	setup = function(node, context)
		for name in pairs(node.attrs) do
			if APP_ONLY[name] then node.attrs[name] = nil end
		end
		node.width = node:number("width")
		node.height = node:number("height")
		node.fill = node:color("background")
		node.states = node:value("states")
		node.cameraName = node:value("camera")
		node.environmentIntensity = tonumber(node.attrs.environmentIntensity) or 1
		local view = { node = node, native = context.native.scene(), records = {}, roots = {}, byId = {} }
		node.view = view
		buildRecords(view, node.element, nil, context)
		if not view.cameras then node:fail("needs a <Camera>") end
		if node.attrs.environment then
			local image = node:value("environment")(0)
			if type(image) == "table" then image = image.image end
			view.native:environment(image, node.environmentIntensity)
		end
		if not rawget(context.env, "project") then
			rawset(context.env, "project", function(id, point) return World.project(context, id, point) end)
		end
		if node.attrs.id then
			context.sceneViews = context.sceneViews or {}
			context.sceneViews[node.attrs.id] = node
		end
	end,
	paint = function(node, rc, t)
		local view = node.view
		local w = node.width and Scene.value(node.width, t) or rc.scene.width
		local h = node.height and Scene.value(node.height, t) or rc.scene.height
		local states = {}
		if node.states then
			for _, state in ipairs(node.states(t) or {}) do states[state.id] = state end
		end
		for _, record in ipairs(view.roots) do pose(view, record, t, states, true) end
		for _, record in ipairs(view.records) do
			if record.surface and record.visible then paintSurface(view, record, rc, t) end
		end
		local camera = view.cameras[1]
		if node.cameraName then
			local name = node.cameraName(t)
			camera = view.byId[name] or node:fail("has no camera " .. tostring(name))
			if camera.tag ~= "Camera" then node:fail(name .. " is not a <Camera>") end
		end
		local zoom = rc.pen.zoom
		local pw, ph = min(MAX_PIXELS, max(1, floor(w * zoom + 0.5))), min(MAX_PIXELS, max(1, floor(h * zoom + 0.5)))
		node.frame = { camera = camera, w = w, h = h }
		local fill = node.fill and Scene.value(node.fill, t)
		if fill then rc.pen:rect(0, 0, w, h, fill) end
		rc.pen.canvas:image(view.native:render(camera.handle, pw, ph), 0, 0, w, h)
	end,
}

-- project(viewId, {x, y, z}) -> {x, y, depth}: where a world point was drawn
-- in the named <SceneView>'s units (plus its position) this frame. Overlays
-- after the view in document order can pin crisp type to a 3-D point.
function World.project(context, id, point)
	local node = context.sceneViews and context.sceneViews[id]
	if not node then error("reel: no <SceneView id=\"" .. tostring(id) .. "\">", 2) end
	local frame = node.frame
	if not frame then return { -1e4, -1e4, -1 } end
	local x, y, depth = node.view.native:project(frame.camera.handle, frame.w, frame.h, point[1], point[2], point[3])
	return { x, y, depth }
end

-- <Surface width height density slot background>: the screen of the
-- enclosing <Node>, drawn with ordinary reel elements in `width` × `height`
-- points at `density` pixels per point (2 by default) and shown in the
-- material's `slot`, "emission" (self-lit, by default) or "diffuse".
World.Surface = {
	setup = function(node, context)
		if not context.buildingSurface then node:fail("belongs inside a <Node> of a <SceneView>") end
		node.width = tonumber(node.attrs.width) or node:fail("needs a numeric width")
		node.height = tonumber(node.attrs.height) or node:fail("needs a numeric height")
		node.density = tonumber(node.attrs.density) or 2
		node.slot = node.attrs.slot or "emission"
		node.fill = Scene.parseHex(node.attrs.background or "#000000")
	end,
	bounds = function(node) return { 0, 0, node.width, node.height } end,
}

return World
