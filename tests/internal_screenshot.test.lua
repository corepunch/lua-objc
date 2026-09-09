local t = require("TestKit")

local source = assert(io.open("src/main.m", "r")):read("*a")
t.expect(source:find("CGFloat captureWidth", 1, true) ~= nil
		and source:find("CGFloat captureHeight", 1, true) ~= nil,
	"internal screenshots honor explicit requested dimensions")
t.expect(source:find("captureWidth, captureHeight", 1, true) ~= nil,
	"internal screenshots render using the requested capture frame")

t.expect(source:find('capture.arguments = @[@"-x", @"-l"', 1, true) ~= nil,
	"native screenshot passes paths as arguments without shell interpolation")
t.expect(source:find('capture.terminationStatus == 0', 1, true) ~= nil,
	"native capture rejects command failures")
t.expect(source:find('exit(png.length ? EXIT_SUCCESS : EXIT_FAILURE)', 1, true) ~= nil,
	"missing native screenshot fails process status")
t.expect(source:find('exit(captured ? EXIT_SUCCESS : EXIT_FAILURE)', 1, true) ~= nil,
	"internal write failure fails process status")

os.exit(t.summary() and 0 or 1)
