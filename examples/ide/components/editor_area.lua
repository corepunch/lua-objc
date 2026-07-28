local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")

local function fill(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- EditorArea: one native window-tab document surface. The code editor and its
-- preview canvas share an inner NSSplitView owned by that document window.
local function EditorArea(props)
	props = props or {}

	return ns.HSplit {
		flexGrow = props.flexGrow or 1,
		proportions = props.proportions or { 1, 1 },
		fill(props.editor or props.content),
		fill(props.preview),
	}
end

return EditorArea
