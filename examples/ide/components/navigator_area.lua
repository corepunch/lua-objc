local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- NavigatorArea: left sidebar panel.
-- Props: title, content (view).
-- Mirrors Xcode's IDENavigatorArea / NSView_ControlledBy_IDENavigatorArea.
local function NavigatorArea(props)
	props = props or {}
	return ns.VStack {
		spacing = 0,
		ControlBar { title = props.title },
		wrapContent(props.content),
	}
end

return NavigatorArea
