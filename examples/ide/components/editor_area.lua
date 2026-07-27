local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- EditorArea: centre editing panel.
-- Props: title, content (view), leading/buttons ControlBar items.
-- Mirrors Xcode's IDEEditorArea / DVTSplitView_ControlledBy_IDEEditorArea.
local function EditorArea(props)
	props = props or {}
	return ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		ControlBar {
			title = props.title,
			leading = props.leading,
			buttons = props.buttons or props.trailing,
		},
		wrapContent(props.content),
	}
end

return EditorArea
