local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("props.style or \"automatic\"", 1, true) ~= nil,
	"UIKit Picker forwards style")
t.expect(native:find("UISegmentedControl", 1, true) ~= nil
		and native:find("UIMenu", 1, true) ~= nil
		and native:find("UIPickerView", 1, true) ~= nil,
	"UIKit Picker maps styles to native controls")
t.expect(native:find("Picker style must be segmented", 1, true) ~= nil,
	"UIKit Picker rejects unknown styles")
t.expect(xml:find('style = "str"', 1, true) ~= nil,
	"XML Picker exposes style")

os.exit(t.summary() and 0 or 1)
