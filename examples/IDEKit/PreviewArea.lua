local ns = require("AppKit")
local bridge = require("AppKitNative")

local PANEL = {
	headerHeight = 34,
}

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

local function PreviewArea(props)
	props = props or {}

	local toolbarRow = ns.HStack {
		flexGrow = 0,
		flexShrink = 0,
		spacing = 4,
	}

	local canvas = props.canvas
	local area = wrapContent(canvas)

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
		if area then area:layout() end
	end

	local self = {
		view = area,
		setContent = function(_, result, toolbarItems)
			rebuildToolbar(toolbarItems)
		end,
	}

	return self
end

return PreviewArea
