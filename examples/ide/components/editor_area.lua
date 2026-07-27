local ns = require("AppKit")
local bridge = require("bridge")
local ControlBar = require("examples.ide.components.control_bar")

-- EditorArea: centre editing panel.
-- New API (no title): returns area VStack + native NSTabView.
-- Legacy API (props.title set): returns ControlBar area.
local function EditorArea(props)
	props = props or {}

	if props.title then
		local content = props.content
		if content then
			content.flexGrow = 1
			content.fillWidth = true
		end
		return ns.VStack {
			flexGrow = props.flexGrow or 1,
			spacing = 0,
			ControlBar {
				title = props.title,
				leading = props.leading,
				buttons = props.buttons or props.trailing,
			},
			content,
		}
	end

	local tabView = bridge._tabview(400, 200, "top")
	tabView.flexGrow = 1
	tabView.fillWidth = true

	local area = ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		tabView,
	}

	return area, tabView
end

return EditorArea
