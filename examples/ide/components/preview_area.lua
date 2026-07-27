local ns = require("AppKit")
local ControlBar = require("examples.ide.components.control_bar")
local bridge = require("bridge")

local PreviewArea = {}

local PANEL = {
	headerHeight = 34,
}

PreviewArea._toolbarTarget = nil
PreviewArea._toolbarParent = nil

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- rebuildToolbar: rebuild toolbar buttons in the CANVAS ControlBar.
-- Items is an array of {icon, tooltip} descriptors from the canvas eval,
-- or nil to clear all buttons.
function PreviewArea.rebuildToolbar(items)
	local target = PreviewArea._toolbarTarget
	local parent = PreviewArea._toolbarParent
	if not target then return end

	bridge._clearContainer(target)
	if items then
		for _, item in ipairs(items) do
			if item.icon then
				local btn = bridge._symbolButton(item.icon, item.tooltip or item.label)
				bridge._add(target, btn)
			end
		end
	end
	if parent then bridge._layout(parent) end
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
	local area = ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		ControlBar {
			title = props.title or "Canvas",
			height = PANEL.headerHeight,
			leading = props.leading,
			buttons = { toolbarRow },
		},
		wrapContent(props.content),
	}
	PreviewArea._toolbarTarget = toolbarRow
	PreviewArea._toolbarParent = area
	return area
end

return PreviewArea
