_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Mail = require("examples.mail.Controller")

local controller = Mail.new()
local window = controller:createWindow()
local state = window:workspaceState()

t.expect(state ~= nil, "mail directory launch builds a native workspace window")
t.expect(state.itemCount == 3,
	"mail launched with sidebar, message list, and detail split items")
t.expect(state.nativeSidebar,
	"mail launched with AppKit semantic sidebar")
t.expect(state.fullHeightSidebar,
	"mail sidebar participates in full-height layout")
t.expect(window.size.width >= 640,
	"mail window has usable launch width")
t.expect(window.size.height >= 400,
	"mail window has usable launch height")

os.exit(t.summary() and 0 or 1)
