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

-- A wrapped label is as tall as the lines its cell draws (#59). The cell
-- avoids a short last line, so this text takes three lines in 471 points
-- where a plain text container fits it in two; the third line was clipped.
local wrapped = render([[<VStack><ContentUnavailable title="No Duplicates Listed" systemImage="doc.on.doc"
	description="Add a folder such as Downloads or Documents, then choose Find Duplicates. Files are compared byte for byte; nothing is read outside the folders you add." /></VStack>]], {}, ns)
wrapped.size = ns.Size(942, 500); wrapped:layout(942)
local text = wrapped.subviews[1].subviews[4].subviews[2]
local line = ns.Text { "One line" }
t.assertEqual(text.frame.size.width, 471, "the description wraps in half the pane")
t.expect(text.frame.size.height >= 3 * math.floor(line.fittingSize.height), "a wrapped label is as tall as the lines it draws")

-- NSTextAlignment numbers differ between Intel and Apple silicon, so
-- alignment names resolve to the compiled constants, never Lua literals.
local label = ns.Text { "Aligned", alignment = "center" }
t.assertEqual(label.textAlignment, bridge._textAlignment("center"), "centered text uses AppKit's center constant")
t.expect(bridge._textAlignment("center") ~= bridge._textAlignment("trailing"), "center and trailing stay distinct")
t.assertEqual(bridge._textAlignment("justified"), 3, "justified is the same on every architecture")
local leading = render([[<ContentUnavailable title="Drop" description="Drag a folder here." descriptionAlignment="leading" />]], {}, ns)
t.assertEqual(leading.subviews[3].subviews[2].textAlignment, bridge._textAlignment("leading"), "an unavailable view can lead-align its description")

-- SwiftUI's `actions:` slot: child controls sit directly beneath the
-- message and are centered with it, never pinned to the pane's bottom.
local tapped = 0
local actionRoot, actionRefs = render([[<VStack spacing="0">
	<ContentUnavailable id="empty" title="Nothing Here" systemImage="folder" description="This folder is empty.">
		<Button id="next" title="Add a Folder" action="add" />
	</ContentUnavailable>
</VStack>]], { actions = { add = function() tapped = tapped + 1 end } }, ns)
actionRoot.size = ns.Size(600, 400)
actionRoot:layout(600)
t.assertSize(actionRefs.empty, 600, 400, "an unavailable message with actions still fills the pane")
local pieces = actionRefs.empty.subviews
t.assertEqual(#pieces, 6, "actions add one group between the description and the trailing spacer")
local top, bottom = pieces[1].frame.size.height, pieces[#pieces].frame.size.height
t.expect(top > 50 and math.abs(top - bottom) < 0.5, "message and actions are centered together")
local descriptionFrame, group = pieces[4].frame, pieces[5].frame
-- AppKit frames here are bottom-up, so "beneath" is a smaller y.
local gap = descriptionFrame.origin.y - (group.origin.y + group.size.height)
t.expect(gap >= 0, "actions follow the description")
t.expect(gap < 40, "actions stay beside the message, not at the pane's bottom edge")
local next = actionRefs.next
local nextX = group.origin.x + next.frame.origin.x + next.frame.size.width / 2
t.expect(math.abs(nextX - 300) < 1, "an action is centered horizontally")
t.expect(next.frame.size.width < 300, "an action keeps its intrinsic width")
t.expect(uikit:find("for _, action in ipairs(props) do table.insert(actions, action) end", 1, true) ~= nil,
	"UIKit ContentUnavailable places action children too")

os.exit(t.summary() and 0 or 1)
