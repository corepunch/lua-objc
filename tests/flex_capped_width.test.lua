_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local xml = require("ui.xml")
local root, refs = xml.render([[<HStack spacing="0" height="300">
	<VStack width="68" />
	<VStack id="stage" flexGrow="1" minWidth="280" maxWidth="440"><Label text="Preview" /></VStack>
	<VStack id="chat" flexGrow="1" maxWidth="infinity"><Label text="Chat" /></VStack>
</HStack>]],{},ns)
for _, width in ipairs({834,1194,744}) do
	root.size = ns.Size(width,300); root:layout(width)
	local stage, chat = refs.stage.frame, refs.chat.frame
	t.expect(stage.size.width <= 440,"a flex child respects its maximum at " .. width)
	t.expect(stage.size.width >= 280,"a flex child respects its minimum at " .. width)
	t.expect(chat.origin.x + chat.size.width <= width + 1,"flex siblings fit the parent's width at " .. width)
	t.expect(chat.size.width > 250,"chat receives remaining space at " .. width)
end
os.exit(t.summary() and 0 or 1)
