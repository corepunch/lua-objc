_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")

local function mid(bounds)
	return bounds.origin.x + bounds.size.width / 2, bounds.origin.y + bounds.size.height / 2
end

local function arc(startAngle, endAngle)
	return ns.Arc {
		startAngle = startAngle, endAngle = endAngle,
		lineWidth = 3, width = 48, height = 48, stroke = "accent",
	}
end

local northX, northY = mid(arc(247.5, 292.5):arcBounds())
t.expect(math.abs(northX - 24) < 4, "north arc stays centered")
t.expect(northY < 12, "north arc sits in the top of the compass")

local eastX, eastY = mid(arc(-22.5, 22.5):arcBounds())
t.expect(eastX > 36, "east arc sits on the right")
t.expect(math.abs(eastY - 24) < 6, "east arc stays on the horizontal center")

local southX, southY = mid(arc(67.5, 112.5):arcBounds())
t.expect(math.abs(southX - 24) < 4, "south arc stays centered")
t.expect(southY > 36, "south arc sits in the bottom of the compass")

local westX, westY = mid(arc(157.5, 202.5):arcBounds())
t.expect(westX < 12, "west arc sits on the left")
t.expect(math.abs(westY - 24) < 6, "west arc stays on the horizontal center")

local circle = arc(0, 360)
local bounds = circle:arcBounds()
t.expect(bounds.size.width > 46 and bounds.size.height > 46, "a full turn draws the compass ring")
circle.strokeAlpha = 0
t.assertEqual(circle.strokeAlpha, 0, "an unavailable section can be hidden without removing it")
circle.stroke = "tertiary"
t.assertEqual(circle.stroke, "tertiary", "a drag preview can recolor one section")

-- SwiftUI centers a stroke on the shape's path and never clips it to the
-- frame: a 3 pt ring in a 48 pt frame draws 1.5 pt past every edge.
local bridge = require("AppKitNative")
local ink = bridge._arcInkBounds(arc(0, 360), 8)
t.expect(ink.origin.x <= -1 and ink.origin.y <= -1, "the ring's stroke extends past the top-left of its frame")
t.expect(ink.origin.x + ink.size.width >= 49 and ink.origin.y + ink.size.height >= 49,
	"the ring's stroke extends past the bottom-right of its frame")
t.expect(ink.size.width >= 50, "a full circle uses its lineWidth, not a 1 pt default")
local northInk = bridge._arcInkBounds(arc(247.5, 292.5), 8)
t.expect(northInk.origin.y < 0 and northInk.origin.y + northInk.size.height < 12,
	"the north section renders at the top, unclipped")
local eastInk = bridge._arcInkBounds(arc(-22.5, 22.5), 8)
t.expect(eastInk.origin.x + eastInk.size.width > 48, "the east section renders past the right edge, unclipped")

-- UIKit draws through the same unclipped shape layer.
local file = assert(io.open("src/uikit/views.m")); local uikit = file:read("*a"); file:close()
local arcView = uikit:match("@implementation LuaArcView(.-)@end")
t.expect(arcView:find("layerClass { return CAShapeLayer.class; }", 1, true) ~= nil, "UIKit Arc is backed by a shape layer")
t.expect(not arcView:find("drawRect", 1, true), "UIKit Arc never draws into its clipped backing store")

os.exit(t.summary() and 0 or 1)
