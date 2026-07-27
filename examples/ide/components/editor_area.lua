local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")
local EditorTabBar = require("examples.ide.components.editor_tab_bar")

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- EditorArea: centre editing panel.
-- New API (tabbed): no title, uses EditorTabBar. Requires
--   onTabChange and saveFn callbacks.
-- Legacy API: props.title, props.content, props.buttons → ControlBar.
-- Mirrors Xcode's IDEEditorArea with NSTabView-style tab bar.
local function EditorArea(props)
	props = props or {}

	-- New API: tabbed editor (no title, has onTabChange/saveFn).
	if not props.title then
		local tabBar = EditorTabBar {
			onTabChange = props.onTabChange,
			saveFn = props.saveFn,
		}

		return ns.VStack {
			flexGrow = props.flexGrow or 1,
			spacing = 0,
			tabBar._strip,
			ns.Separator(),
			wrapContent(props.content),
		}, tabBar
	end

	-- Legacy API: ControlBar-based.
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
