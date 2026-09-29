-- Bespoke shots drawn with the pen (Reel's `<Draw with="…">`): the screens
-- whose components move (Motion.lua), and the voice pill.
local Reel = require("Reel")
local Motion = require("Motion")
local Shape, rgb = Reel.Shape, Reel.rgb
local progress, spring = Reel.curves.progress, Reel.curves.spring

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

return shots
