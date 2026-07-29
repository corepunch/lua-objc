local ns = require("AppKit")
local ControlBar = require("examples.IDEKit.ControlBar")

local function fill(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

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
