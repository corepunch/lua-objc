local ns = require("AppKit")

-- WorkspaceLayout: the window owns only the navigator/content split.
-- The source editor owns its code/canvas split so both travel together when
-- AppKit moves a document tab into another window.
local function WorkspaceLayout(props)
	props = props or {}
	return ns.HSplit {
		flexGrow = 1,
		proportions = props.proportions or { 1, 4 },
		props.navigator,
		props.editor,
	}
end

return WorkspaceLayout
