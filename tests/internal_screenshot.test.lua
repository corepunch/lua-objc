local t = require("TestKit")

local source = assert(io.open("src/main.m", "r")):read("*a")
-- The window is resized to the requested size, clamped to its minimum as a
-- drag is; the screenshot renders the size the window actually has.
t.expect(source:find("offscreen_render(window.contentView, size.width, size.height)", 1, true) ~= nil,
	"internal screenshots render the window's actual content size")

t.expect(source:find('capture.arguments = @[@"-x", @"-l"', 1, true) ~= nil,
	"native screenshot passes paths as arguments without shell interpolation")
t.expect(source:find('capture.terminationStatus == 0', 1, true) ~= nil,
	"native capture rejects command failures")
t.expect(source:find('exit(png.length ? EXIT_SUCCESS : EXIT_FAILURE)', 1, true) ~= nil,
	"missing native screenshot fails process status")
t.expect(source:find('exit(captured ? EXIT_SUCCESS : EXIT_FAILURE)', 1, true) ~= nil,
	"internal write failure fails process status")

os.exit(t.summary() and 0 or 1)
