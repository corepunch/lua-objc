_G.__headless = true

local t = require("TestKit")
local Mail = require("examples.mail.Controller")

local controller = Mail.new()
local window = controller:createWindow()
local state = window:workspaceState()

t.expect(state ~= nil, "mail window uses native workspace composition")
t.assertEqual(state.itemCount, 3,
	"mail window has sidebar, message list, and detail split items")
t.expect(state.nativeSidebar,
	"mail window uses AppKit's semantic sidebar")
t.expect(state.fullHeightSidebar,
	"mail sidebar participates in full-height window layout")
t.expect(state.tracksContentDivider,
	"mail content/detail divider continues through the toolbar")
t.expect(state.hasSidebarToggle,
	"mail toolbar includes the standard sidebar toggle")

t.expect(controller.mailboxList.size.width >= 160,
	"mail sidebar has usable native width")
t.expect(controller.messageList.size.width >= 240,
	"mail message list keeps a usable column width")
t.expect(controller.detailPane.size.width > controller.messageList.size.width,
	"mail detail pane gets the primary flexible space")

os.exit(t.summary() and 0 or 1)