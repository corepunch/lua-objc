local t = require("TestKit")

if package.loaded.UIKitNative then
	local ns = require("UIKit")
	for _, style in ipairs({ "default", "plain", "link" }) do
		local button = ns.Button { title = "Look around", style = style }
		t.assertEqual(button.contentHorizontalAlignment, 0, style .. " button content is centered")
		ns._parityMeasure(button, {}, { width = 240, height = 44 })
		local label = button.titleLabel.frame
		t.expect(math.abs(label.origin.x + label.size.width / 2 - 120) < 1,
			style .. " title stays centered in an expanded button")
		t.assertEqual(button.titleLabel.text, "Look around", "layout preserves the button title")
	end
	return t.summary()
end

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/constructors.m", "r")):read("*a")

t.expect(src:find("props.systemImage", 1, true) ~= nil
		and src:find("props.role", 1, true) ~= nil,
	"UIKit Button forwards symbol and role")
t.expect(native:find("configuration.image", 1, true) ~= nil
		and native:find("systemRedColor", 1, true) ~= nil,
	"UIKit Button uses native image and destructive styling")
t.expect(native:find("borderedProminentButtonConfiguration", 1, true) ~= nil,
	"UIKit Button uses current bordered prominent configuration")
local plain = native:match('strcmp%(style, "link"%) == 0%) {(.-)\n\t} else if')
t.expect(plain and plain:find("contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter", 1, true)
	and not plain:find("UIControlContentHorizontalAlignmentLeft", 1, true),
	"plain, default, and link buttons center their native content")

os.exit(t.summary() and 0 or 1)
