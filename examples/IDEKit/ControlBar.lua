local ns = require("AppKit")

local function ControlBar(props)
	props = props or {}
	local height = props.height or 28

	local function edgeGroup(controls)
		return ns.HStack {
			spacing = 4,
			flexGrow = 0,
			flexShrink = 0,
			table.unpack(controls),
		}
	end

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

	return ns.VStack {
		fixedHeight = height + 1,
		flexGrow = 0,
		fillWidth = true,
		spacing = 0,
		ns.HStack(rowItems),
		ns.Separator(),
	}
end

return ControlBar
