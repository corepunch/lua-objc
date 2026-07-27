local ns = require("AppKit")

-- ControlBar: thin header strip, like Xcode's DVTControlBar.
-- Props: title (string), height (number, default 28), leading/buttons (view arrays).
local function ControlBar(props)
	props = props or {}
	local height = props.height or 28

	-- Edge groups must retain their intrinsic width. HStack normally expands on
	-- its main axis, which would make a trailing button group occupy half the
	-- header and visually center its controls instead of pinning them right.
	local function edgeGroup(controls)
		return ns.HStack {
			spacing = 4,
			flexGrow = 0,
			flexShrink = 0,
			table.unpack(controls),
		}
	end

	-- Row of items: leading | title | Spacer | buttons
	local rowItems = {
		fixedHeight = height,
		paddingHorizontal = 8,
		alignment = "center",
		spacing = 6,
	}
	if props.leading then
		rowItems[#rowItems + 1] = edgeGroup(props.leading)
	end
	if props.title then
		rowItems[#rowItems + 1] = ns.Text {
			props.title,
			size = 11,
			weight = "semibold",
			color = "secondary",
		}
	end
	rowItems[#rowItems + 1] = ns.Spacer()
	local buttons = props.buttons or props.trailing
	if buttons then
		rowItems[#rowItems + 1] = edgeGroup(buttons)
	end

	-- fixedHeight pins the total bar height; flexGrow=0 prevents vertical expansion.
	-- fillWidth=true makes it span the full column width inside HSplit.
	return ns.VStack {
		fixedHeight = height + 1,   -- row + 1px separator
		flexGrow = 0,
		fillWidth = true,
		spacing = 0,
		ns.HStack(rowItems),
		ns.Separator(),
	}
end

return ControlBar
