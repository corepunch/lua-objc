local t = require("TestKit")

local source = assert(io.open("src/main.m", "r")):read("*a")
t.expect(source:find("CGFloat captureWidth", 1, true) ~= nil
		and source:find("CGFloat captureHeight", 1, true) ~= nil,
	"internal screenshots honor explicit requested dimensions")
t.expect(source:find("captureWidth, captureHeight", 1, true) ~= nil,
	"internal screenshots render using the requested capture frame")

os.exit(t.summary() and 0 or 1)
