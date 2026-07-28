local ns = require("AppKit")

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- NavigatorArea: a standard source-list sidebar with one file tree.
-- Search and other workspace-wide commands belong in menus or toolbar items,
-- so the navigator does not need a second, app-defined tab strip.
local function NavigatorArea(props)
	props = props or {}
	return ns.VStack {
		spacing = 0,
		wrapContent(props.content),
	}
end

return NavigatorArea
