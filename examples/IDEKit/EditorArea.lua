local ns = require("AppKit")

local function EditorArea(props)
	props = props or {}

	local textView = ns.TextEditor {
		language = props.language or "lua",
		wrapMode = props.wrapMode ~= false,
		flexGrow = 1,
		fillWidth = true,
	}

	local editorPane = ns.VStack {
		flexGrow = 1,
		fillWidth = true,
		spacing = 0,
		textView,
	}

	local self = {
		view = editorPane,
		textView = textView,
	}

	return self
end

return EditorArea
