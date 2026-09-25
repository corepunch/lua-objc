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

os.exit(t.summary() and 0 or 1)
