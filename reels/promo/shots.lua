-- Bespoke shots drawn with the pen (Reel's `<Draw with="…">`): the screens
-- whose components move (Motion.lua), the MVC code panels, the request
-- bubble and the caption pill.
local Reel = require("Reel")
local Motion = require("Motion")
local Shape, rgb = Reel.Shape, Reel.rgb
local progress, spring = Reel.curves.progress, Reel.curves.spring
local ease = Reel.curves.easing

local shots = {}

-- <Draw with="phone" timeline="pair" />: the iPhone's screen through a
-- timeline from the reel data (data.phones[name]). Taps aimed at a
-- component are resolved to its centre when the reel loads.
shots.phone = {
	setup = function(node, context)
		local name = node.attrs.timeline or node:fail("needs a timeline")
		node.spec = context.data.phones[name] or node:fail("no phone timeline " .. name)
		node.native = context.native
		for _, tap in ipairs(node.spec.taps or {}) do
			if tap.aim then
				local r = Motion.part(node.spec, node.native, tap.aim[1], tap.aim[2])
					or node:fail("tap aims at a missing " .. tap.aim[2] .. " in " .. tap.aim[1])
				tap.x, tap.y = r.x + r.w * (tap.aim[3] or 0.5), r.y + r.h * (tap.aim[4] or 0.5)
			end
		end
	end,
	draw = function(pen, t, node) Motion.phone(pen, t, node.spec, node.native) end,
}

-- <Draw with="studio" session="pair" />: Lua Studio on the iPad through a
-- session from the reel data (data.studios[name]).
shots.studio = {
	setup = function(node, context)
		local name = node.attrs.session or node:fail("needs a session")
		node.spec = context.data.studios[name] or node:fail("no studio session " .. name)
		node.native = context.native
	end,
	draw = function(pen, t, node) Motion.studio(pen, t, node.spec, node.native) end,
}

-- <Draw with="caption" text="Ask." at="5.0" exit="6.9" />: a word on a
-- dark pill at the foot of the frame, springing up on its beat and away at
-- its exit, so it reads over any screen.
local CAPTION = { size = 58, padX = 34, height = 96, y = 950, rise = 40 }
local CAPTION_TYPE = Reel.Pen.style(CAPTION.size, "bold", 0xF5F5F7, -0.03)
shots.caption = {
	setup = function(node)
		node.text = node.attrs.text or node:fail("needs text")
		node.at = tonumber(node.attrs.at) or node:fail("needs a numeric at")
		node.exit = tonumber(node.attrs.exit) or node:fail("needs a numeric exit")
		node:addEvent(node.at, "pop")
	end,
	draw = function(pen, t, node)
		if t < node.at or t > node.exit + 0.3 then return end
		local k = spring(t - node.at, 0.42, 0.62)
		local out = Reel.curves.easing.inCubic(progress(t, node.exit, node.exit + 0.25))
		local w = pen:width(node.text, CAPTION_TYPE) + CAPTION.padX * 2
		local h = CAPTION.height
		pen:save()
		pen:translate(960, CAPTION.y + CAPTION.rise * (1 - k) + 30 * out)
		pen:scale(0.86 + 0.14 * k)
		pen:fade(math.min(1, (t - node.at) / 0.1) * (1 - out))
		pen:shadow({ dy = 12, blur = 40, color = { 0, 0, 0, 0.45 } })
		pen:fill(Shape.roundedRect(-w / 2, -h / 2, w, h, h / 2), rgb(0x16161A, 0.86))
		pen:shadow()
		pen:stroke(Shape.roundedRect(-w / 2, -h / 2, w, h, h / 2), rgb(0xFFFFFF, 0.12), 1.5)
		pen:text(node.text, CAPTION_TYPE, 0, CAPTION.size * 0.36, "center")
		pen:restore()
	end,
}

-- <Draw with="layer" layer="1" at="14.0" />: one layer of the agent's
-- filter edit on a code panel (720 × 156 pt): its role, its file and line
-- counts, and its first changed lines of code wiping in. The layers come
-- from the edit's own patch (data.layers, init.lua).
local LAYER = { w = 720, h = 156, inset = 26, header = 46, first = 88, step = 27, wipe = 0.3, gap = 0.12,
	background = 0x15151B }
local LAYER_TYPE = {
	role = Reel.Pen.style(15, "bold", 0xF5F5F7, 0.08),
	file = { size = 21, weight = "semibold", kern = 0, color = rgb(0xF5F5F7), design = "mono" },
	note = Reel.Pen.style(17, "regular", 0x8E8E93, -0.01),
	added = { size = 17, weight = "medium", kern = 0, color = rgb(0x30D158), design = "mono" },
	code = { size = 17, weight = "regular", kern = 0, color = rgb(0xE5E5EA), design = "mono" },
	sign = { size = 17, weight = "semibold", kern = 0, color = rgb(0x30D158), design = "mono" },
}
LAYER.columns = 58
shots.layer = {
	setup = function(node, context)
		local index = tonumber(node.attrs.layer) or node:fail("needs a layer")
		node.layer = context.data.layers[index] or node:fail("no layer " .. index)
		node.at = tonumber(node.attrs.at) or node:fail("needs a numeric at")
	end,
	draw = function(pen, t, node)
		local L = node.layer
		local x = LAYER.inset
		-- The role, as a chip in its colour.
		local roleWidth = pen:width(L.role:upper(), LAYER_TYPE.role) + 24
		pen:fill(Shape.roundedRect(x, 20, roleWidth, 30, 15), rgb(L.color, 0.22))
		pen:text(L.role:upper(), Reel.Pen.style(15, "bold", L.color, 0.08), x + 12, 40.5, "leading")
		local fileX = x + roleWidth + 14
		local fileWidth = pen:text(L.file, LAYER_TYPE.file, fileX, 42, "leading")
		pen:text(L.note, LAYER_TYPE.note, fileX + fileWidth + 12, 42, "leading")
		pen:text(L.delta, LAYER_TYPE.added, LAYER.w - x, 42, "trailing")
		pen:rect(x, LAYER.header + 10, LAYER.w - 2 * x, 1, rgb(0xFFFFFF, 0.1))
		for i, line in ipairs(L.lines) do
			local y = LAYER.first + (i - 1) * LAYER.step
			local text = #line > LAYER.columns and line:sub(1, LAYER.columns - 1) .. "…" or line
			pen:text("+", LAYER_TYPE.sign, x, y, "leading")
			pen:text(text, LAYER_TYPE.code, x + 22, y, "leading")
			-- Each line wipes in after the panel lands, one after another.
			local start = node.at + 0.25 + (i - 1) * LAYER.gap
			local u = ease.outCubic(progress(t, start, start + LAYER.wipe))
			if u < 1 then
				pen:rect(x + (LAYER.w - x) * u, y - 20, (LAYER.w - x) * (1 - u) + 2, 26, LAYER.background)
			end
		end
	end,
}
shots.LAYER = LAYER

-- <Draw with="request" text="Add a filter." x="130" y="330" at="13.5" exit="17.3" />:
-- the user's request as Lua Studio draws it, a bubble in the brand
-- gradient, springing up on its beat.
local REQUEST = { size = 40, padX = 30, height = 76, colors = { 0x5856D6, 0xAF52DE, 0xFF2D55 } }
local REQUEST_TYPE = Reel.Pen.style(REQUEST.size, "medium", 0xFFFFFF, -0.015)
shots.request = {
	setup = function(node)
		node.text = node.attrs.text or node:fail("needs text")
		node.at = tonumber(node.attrs.at) or node:fail("needs a numeric at")
		node.exit = tonumber(node.attrs.exit) or node:fail("needs a numeric exit")
	end,
	draw = function(pen, t, node)
		if t < node.at or t > node.exit + 0.3 then return end
		local k = spring(t - node.at, 0.45, 0.62)
		local out = Reel.curves.easing.inCubic(progress(t, node.exit, node.exit + 0.25))
		local w = pen:width(node.text, REQUEST_TYPE) + REQUEST.padX * 2
		local h = REQUEST.height
		local bubble = Shape.roundedRect(0, -h / 2, w, h, h / 2)
		pen:save()
		-- The reel places the node at its x and y: the bubble's leading
		-- edge and its middle.
		pen:translate(0, 30 * (1 - k))
		pen:scale(0.8 + 0.2 * k)
		pen:fade(math.min(1, (t - node.at) / 0.1) * (1 - out))
		pen:shadow({ dy = 14, blur = 40, color = { 0.35, 0.2, 0.8, 0.45 } })
		pen:fill(bubble, REQUEST.colors[2])
		pen:shadow()
		pen:save()
		pen:clip(bubble)
		pen:linear(0, -h / 2, w, h / 2, REQUEST.colors)
		pen:restore()
		pen:text(node.text, REQUEST_TYPE, REQUEST.padX, REQUEST.size * 0.36, "leading")
		pen:restore()
	end,
}

return shots
