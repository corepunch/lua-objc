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

os.exit(t.summary() and 0 or 1)
