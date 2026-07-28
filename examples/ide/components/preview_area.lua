local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")
local bridge = require("bridge")

local PreviewArea = {}

local PANEL = {
	headerHeight = 34,
}

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- PreviewArea: canvas / preview panel.
-- Props: title, content (view).
-- Mirrors Xcode's macOS preview: a real content view hosted inline (no chrome).
-- The canvas intercept (ns.Window to ns.VStack) is already equivalent to
-- Xcode's approach of displaying content-only with no NSWindow frame.
function PreviewArea.show(props)
	props = props or {}
	local toolbarRow = ns.HStack {
		flexGrow = 0,
		flexShrink = 0,
		spacing = 4,
	}
	-- local area = ns.VStack {
	-- 	flexGrow = props.flexGrow or 1,
	-- 	spacing = 0,
	-- 	ControlBar {
	-- 		title = props.title or "Canvas",
	-- 		height = PANEL.headerHeight,
	-- 		leading = props.leading,
	-- 		buttons = { toolbarRow },
	-- 	},
	-- 	wrapContent(props.content),
	-- }
	local area = wrapContent(props.content)

	local function rebuildToolbar(items)
		bridge._clearContainer(toolbarRow)
		if items then
			for _, item in ipairs(items) do
				if item.icon then
					local btn = bridge._symbolButton(
						item.icon,
						item.tooltip or item.label)
					bridge._add(toolbarRow, btn)
				end
			end
		end
		bridge._layout(area)
	end

	return area, rebuildToolbar
end

return PreviewArea
