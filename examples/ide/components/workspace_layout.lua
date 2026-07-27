local ns = require("AppKit")

-- WorkspaceLayout: root 3-panel HSplit.
-- Props: navigator, editor, preview - each a view produced by the area helpers.
-- Mirrors Xcode's workspace root NSSplitView.
local function WorkspaceLayout(props)
	props = props or {}
	return ns.HSplit {
		flexGrow = 1,
		proportions = { 1, 2, 2 },
		props.navigator,
		props.editor,
		props.preview,
	}
end

return WorkspaceLayout
