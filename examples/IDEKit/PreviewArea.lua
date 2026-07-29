local ns = require("AppKit")
local ControlBar = require("examples.IDEKit.ControlBar")
local bridge = require("AppKitNative")

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

function PreviewArea.show(props)
	props = props or {}
	local toolbarRow = ns.HStack {
		flexGrow = 0,
		flexShrink = 0,
		spacing = 4,
	}
	local area = wrapContent(props.content)

	local function rebuildToolbar(items)
		toolbarRow:clearContainer()
		if items then
			for _, item in ipairs(items) do
				if item.icon then
					local btn = bridge._symbolButton(
						item.icon,
						item.tooltip or item.label)
					toolbarRow:add(btn)
				end
			end
		end
		area:layout()
	end

	return area, rebuildToolbar
end

return PreviewArea
