_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
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
	"mail message-list/detail divider is tracked so actions align after it")
t.expect(state.hasSidebarToggle,
	"mail toolbar includes the standard sidebar toggle")
local filterItem = ns.ToolbarItem(window, "filter")
t.assertEqual(filterItem.label, "Filter",
	"mail filter sits before the tracked divider, over the message column")
local composeItem = ns.ToolbarItem(window, "compose")
t.assertEqual(composeItem.label, "Compose",
	"mail compose sits after the tracked divider with the message actions")
local replyItem = ns.ToolbarItem(window, "reply")
t.assertEqual(replyItem.label, "Reply",
	"mail toolbar exposes reply action")
controller:toggleUnreadFilter()
t.expect(controller.unreadOnlyFilter,
	"mail unread filter toggles on from the toolbar filter action")
controller:toggleUnreadFilter()
t.expect(not controller.unreadOnlyFilter,
	"mail unread filter toggles back off")

t.expect(controller.mailboxList.size.width >= 160,
	"mail sidebar has usable native width")
t.expect(controller.messageList.size.width >= 240,
	"mail message list keeps a usable column width")
t.expect(controller.detailPane.size.width > controller.messageList.size.width,
	"mail detail pane gets the primary flexible space")

os.exit(t.summary() and 0 or 1)