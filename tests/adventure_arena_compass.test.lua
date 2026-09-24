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
t.assertEqual(CompassGesture.direction({ x = 0, y = 24 }, "bottom-left"), "north",
	"AppKit drag coordinates invert the vertical axis")

os.exit(t.summary() and 0 or 1)
