local t = require("TestKit")

local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")

t.expect(constructors:find("UIButtonConfiguration", 1, true) ~= nil,
	"UIKit buttons use native configuration styles")
t.expect(constructors:find("borderedButtonConfiguration", 1, true) ~= nil,
	"UIKit exposes bordered button style")
local borderedStart = assert(constructors:find('if (strcmp(style, "bordered") == 0) {', 1, true))
local prominentStart = assert(constructors:find('} else if (strcmp(style, "borderedProminent") == 0) {', borderedStart, true))
local bordered = constructors:sub(borderedStart, prominentStart)
t.expect(bordered ~= nil and bordered:find("configuration.baseForegroundColor = UIColor.tintColor", 1, true) ~= nil,
	"UIKit bordered buttons use the system tint used by SwiftUI")
t.expect(constructors:find('? UIColor.tintColor : UIColor.labelColor', 1, true) ~= nil,
	"UIKit plain buttons keep the primary label color used by SwiftUI")
t.expect(constructors:find('strcmp(style, "default") == 0', 1, true) ~= nil,
	"UIKit default buttons use the system tint used by SwiftUI")
t.expect(constructors:find('configuration.contentInsets = NSDirectionalEdgeInsetsZero', 1, true) ~= nil,
	"UIKit text-only buttons use SwiftUI's zero vertical content insets")
t.expect(constructors:find("borderedProminentButtonConfiguration", 1, true) ~= nil,
	"UIKit exposes bordered prominent button style")
t.expect(constructors:find('configuration.baseBackgroundColor = UIColor.systemRedColor;\n\t\t\t\tconfiguration.baseForegroundColor = UIColor.whiteColor', 1, true) ~= nil,
	"UIKit destructive prominent buttons use SwiftUI's red fill and white title")
t.expect(constructors:find('strcmp(style, "link")', 1, true) ~= nil,
	"UIKit exposes native link button style")
t.expect(src:find("style = type(props) == \"table\" and props.style", 1, true) ~= nil,
	"UIKit Lua button forwards style")

os.exit(t.summary() and 0 or 1)
