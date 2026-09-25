local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local view = ns.MeshGradient({
	width = 3,
	height = 3,
	points = {
		{0, 0}, {0.5, 0}, {1, 0},
		{0, 0.5}, {0.5, 0.5}, {1, 0.5},
		{0, 1}, {0.5, 1}, {1, 1},
	},
	colors = {
		{ red = 0.01, green = 0.01, blue = 0.03 },
		{ red = 0.12, green = 0.04, blue = 0.28 },
		{ red = 0.02, green = 0.02, blue = 0.06 },
		{ red = 0.18, green = 0.05, blue = 0.22 },
		{ red = 0.85, green = 0.78, blue = 1.00 },
		{ red = 0.08, green = 0.22, blue = 0.55 },
		{ red = 0.00, green = 0.00, blue = 0.02 },
		{ red = 0.25, green = 0.06, blue = 0.18 },
		{ red = 0.01, green = 0.02, blue = 0.05 },
	},
})

t.expect(view ~= nil, "MeshGradient constructs a native view")
t.assertEqual(view.meshWidth, 3, "MeshGradient stores grid width")
t.assertEqual(view.meshHeight, 3, "MeshGradient stores grid height")
t.assertEqual(view.animated, false, "MeshGradient is static until TimelineView starts")

local r, _, b = ns._meshGradientSample(view, 0, 0)
t.expect(math.abs(r - 0.01) < 0.02, "corner sample keeps the top-left red channel")
t.expect(math.abs(b - 0.03) < 0.02, "corner sample keeps the top-left blue channel")

local cr, cg, cb = ns._meshGradientSample(view, 0.5, 0.5)
t.expect(cr > 0.4 and cb > 0.4, "center sample stays near the bright interior node")
t.expect(cg > 0.3, "center sample keeps a high green channel")

local rendered = xml.render([[
	<TimelineView schedule="animation">
		<MeshGradient id="mesh" width="3" height="3" animated="true" />
	</TimelineView>
]], {}, ns)
t.expect(rendered ~= nil, "TimelineView renders a MeshGradient child")
t.assertEqual(rendered.animated, true, "TimelineView(.animation) enables mesh animation")
t.assertEqual(rendered.meshWidth, 3, "XML MeshGradient keeps the 3×3 tweet grid")

local withPoints = xml.render([[
	<MeshGradient width="3" height="3">
		<MeshPoint x="0" y="0" red="1" green="0" blue="0" />
		<MeshPoint x="0.5" y="0" red="0" green="1" blue="0" />
		<MeshPoint x="1" y="0" red="0" green="0" blue="1" />
		<MeshPoint x="0" y="0.5" red="1" green="0" blue="0" />
		<MeshPoint x="0.5" y="0.5" red="1" green="1" blue="1" />
		<MeshPoint x="1" y="0.5" red="0" green="0" blue="1" />
		<MeshPoint x="0" y="1" red="1" green="0" blue="0" />
		<MeshPoint x="0.5" y="1" red="0" green="1" blue="0" />
		<MeshPoint x="1" y="1" red="0" green="0" blue="1" />
	</MeshGradient>
]], {}, ns)
local wr, wg, wb = ns._meshGradientSample(withPoints, 0, 0)
t.expect(wr > 0.8 and wg < 0.2 and wb < 0.2, "MeshPoint children configure corner colors")
