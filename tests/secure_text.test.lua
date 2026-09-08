local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local runtime = assert(io.open("src/appkit/runtime.m", "r")):read("*a")
local constructors = assert(io.open("src/appkit/constructors.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(appkit:find("_secureTextField", 1, true) ~= nil,
	"AppKit selects a secure text field natively")
t.expect(runtime:find("NSSecureTextField", 1, true) ~= nil,
	"AppKit secure fields use NSSecureTextField")
t.expect(constructors:find("secureTextField", 1, true) ~= nil,
	"AppKit registers a secure text field constructor")
t.expect(xml:find("secure", 1, true) ~= nil,
	"XML exposes secure text entry")

os.exit(t.summary() and 0 or 1)
