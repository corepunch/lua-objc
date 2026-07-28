local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")

local function fill(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- EditorArea: one document surface. The code editor and its preview canvas
-- share an inner NSSplitView; document switching belongs to NSWindow tabs.
local function EditorArea(props)
	props = props or {}

	local source = ns.VStack {
		flexGrow = 1,
		spacing = 0,
		ControlBar {
			title = props.title or "SOURCE EDITOR",
			leading = props.leading,
			buttons = props.buttons or props.trailing,
		},
		fill(props.editor or props.content),
	}

	return ns.HSplit {
		flexGrow = props.flexGrow or 1,
		proportions = props.proportions or { 1, 1 },
		source,
		fill(props.preview),
	}
end

return EditorArea
