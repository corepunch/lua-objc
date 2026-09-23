local t = require("TestKit")
local plist = assert(io.open("ios/LuaRuntime/Info.plist", "r")):read("*a")
t.expect(plist:find("<key>CADisableMinimumFrameDurationOnPhone</key>%s*<true/>") ~= nil,
	"iPhone host unlocks the full ProMotion frame-rate range")
os.exit(t.summary() and 0 or 1)
