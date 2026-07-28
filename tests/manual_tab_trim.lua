local ns = require("AppKit")
local bridge = require("bridge")

local function tabs(label, configure)
	local view = bridge._tabview(700, 64, "rounded")
	bridge._tabAdd(view, "Developer", ns.Text "First")
	bridge._tabAdd(view, label, ns.Text "Second")
	if configure then configure(view.tabSelector) end
	view.fixedHeight = 64
	view.fillWidth = true
	return view
end

return ns.Window {
	title = "Tab trim comparison",
	width = 760,
	height = 320,
	ns.VStack {
		spacing = 8,
		padding = 16,
		tabs("Current", nil),
		tabs("No tint", function(selector)
			selector.selectedSegmentBezelColor = nil
		end),
		tabs("Large", function(selector)
			selector.controlSize = 3
		end),
		tabs("Large, no tint", function(selector)
			selector.controlSize = 3
			selector.selectedSegmentBezelColor = nil
		end),
	},
}
