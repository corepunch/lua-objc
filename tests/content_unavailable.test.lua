_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local render = require("ui.xml").render

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

for _, name in ipairs({ "ContentUnavailable" }) do
	t.expect(appkit:find("function AppKit." .. name, 1, true) ~= nil,
		"AppKit exposes native composition " .. name)
	t.expect(uikit:find("function UIKit." .. name, 1, true) ~= nil,
		"UIKit exposes native composition " .. name)
	t.expect(xml:find(name .. " =", 1, true) ~= nil,
		"XML registers " .. name)
end
t.expect(uikit:find("UIKit.SystemImage", 1, true) ~= nil
		and uikit:find("UIKit.Title", 1, true) ~= nil
		and uikit:find("UIKit.Label", 1, true) ~= nil,
	"UIKit ContentUnavailable uses native image and text nodes")


-- SwiftUI's ContentUnavailableView fills the space it is offered and
-- centers its message, without sizing attributes in the template.
local root, refs = render([[<VStack spacing="0">
	<Label text="Header" height="20" />
	<ContentUnavailable id="empty" title="Nothing Here" systemImage="folder" description="This folder is empty." />
</VStack>]], {}, ns)
root.size = ns.Size(600, 400)
root:layout(600)
t.assertSize(refs.empty, 600, 380, "an unavailable message takes the remaining width and height")
local parts = refs.empty.subviews
local above, below = parts[1].frame.size.height, parts[#parts].frame.size.height
t.expect(above > 100 and math.abs(above - below) < 0.5, "its content is centered vertically")
local title = parts[3].frame
t.expect(math.abs(title.origin.x + title.size.width / 2 - 300) < 1, "its title is centered horizontally")

-- The description keeps to the middle half of the pane, centered by default.
local descriptionRow = parts[4]
local description = descriptionRow.subviews[2]
t.expect(math.abs(description.frame.size.width - 300) < 1, "the description is half the pane wide")
t.expect(math.abs(description.frame.origin.x - 150) < 1, "the description's half is centered")
local bridge = require("AppKitNative")
t.assertEqual(description.textAlignment, bridge._textAlignment("center"), "the description is centered by default")

-- NSTextAlignment numbers differ between Intel and Apple silicon, so
-- alignment names resolve to the compiled constants, never Lua literals.
local label = ns.Text { "Aligned", alignment = "center" }
t.assertEqual(label.textAlignment, bridge._textAlignment("center"), "centered text uses AppKit's center constant")
t.expect(bridge._textAlignment("center") ~= bridge._textAlignment("trailing"), "center and trailing stay distinct")
t.assertEqual(bridge._textAlignment("justified"), 3, "justified is the same on every architecture")
local leading = render([[<ContentUnavailable title="Drop" description="Drag a folder here." descriptionAlignment="leading" />]], {}, ns)
t.assertEqual(leading.subviews[3].subviews[2].textAlignment, bridge._textAlignment("leading"), "an unavailable view can lead-align its description")

os.exit(t.summary() and 0 or 1)
