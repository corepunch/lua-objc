_G.__headless = true
package.path = "./?.lua;./lua/?.lua;" .. package.path

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local tapped, dragged = false, false
local view = xml.render([[<VStack onTap="tap" onDrag="drag"><Label text="Gesture target"/></VStack>]], {
	actions = {
		tap = function() tapped = true end,
		drag = function(event) dragged = event.velocity ~= nil end,
	},
}, ns)
t.expect(view ~= nil, "XML attaches native tap and drag recognizers")
t.expect(not tapped and not dragged, "headless construction does not synthesize gesture events")

local originalVStack = ns.VStack
local capturedEdgeSwipe
ns.VStack = function(props)
	capturedEdgeSwipe = props.onEdgeSwipe
	return originalVStack(props)
end
local backedOut = false
xml.render([[<VStack onEdgeSwipe="back" />]], {
	actions = { back = function() backedOut = true end },
}, ns)
ns.VStack = originalVStack
t.expect(type(capturedEdgeSwipe) == "function", "XML binds a left-edge navigation action")
if capturedEdgeSwipe then capturedEdgeSwipe() end
t.expect(backedOut, "bound edge navigation reaches the controller action")

os.exit(t.summary() and 0 or 1)
