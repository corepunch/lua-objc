_G.__headless = true

local t = require("TestKit")
local CompassGesture = require("apps.adventure-arena.services.CompassGesture")

local cases = {
	{ 0, -24, "north" },
	{ 24, -24, "northeast" },
	{ 24, 0, "east" },
	{ 24, 24, "southeast" },
	{ 0, 24, "south" },
	{ -24, 24, "southwest" },
	{ -24, 0, "west" },
	{ -24, -24, "northwest" },
}
for _, case in ipairs(cases) do
	t.assertEqual(CompassGesture.direction({ x = case[1], y = case[2] }), case[3],
		"compass translation maps to " .. case[3])
end

t.assertEqual(CompassGesture.direction({ x = 4, y = 4 }), nil,
	"short drags do not select a direction")

local x, y = CompassGesture.offset({ x = 0, y = 24 })
t.assertEqual(x, 0, "vertical drag has no horizontal displacement")
t.expect(y > 0 and y < 14, "compass movement resists and caps a short drag")
local largeX, largeY = CompassGesture.offset({ x = 200, y = 0 })
t.expect(largeX > 13 and largeX < 14 and largeY == 0,
	"long drag approaches the same bounded distance as SwiftUI")
local upX, upY = CompassGesture.offset({ x = 4, y = -12 })
t.expect(upX > 0 and upY < 0, "upward drags move the compass up in top-left coordinates")
local north
for _, segment in ipairs(CompassGesture.segments()) do
	if segment.direction == "north" then north = segment end
end
t.assertEqual(north.startAngle, 247.5, "north section is centered on the top of the compass")
t.assertEqual(north.endAngle, 292.5, "north section spans one compass sector")

local zeroX, zeroY = CompassGesture.offset({ x = 0, y = 0 })
t.assertEqual(zeroX, 0, "released compass returns to its horizontal origin")
t.assertEqual(zeroY, 0, "released compass returns to its vertical origin")

os.exit(t.summary() and 0 or 1)
