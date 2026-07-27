local ns = require("AppKit")
local bridge = require("bridge")

local NAV = {
	buttonSize = 28,
	spacing = 2,
	paddingHorizontal = 6,
}

-- NavigatorTabBar: Xcode-style navigator tab strip with icon buttons.
-- Props: tabs (array of {id, symbol, tooltip}), selectedId, onSelect(id).
-- Returns the bar view, a buttons table, and select(id) helper.
local function NavigatorTabBar(props)
	props = props or {}
	local tabs = props.tabs or {}
	local selectedId = props.selectedId
	local onSelect = props.onSelect

	local buttons = {}

	local function handleSelect(targetId)
		for _, tab in ipairs(tabs) do
			local btn = buttons[tab.id]
			if btn then
				btn.state = (tab.id == targetId) and 1 or 0
			end
		end
		if onSelect then
			onSelect(targetId)
		end
	end

	for _, tab in ipairs(tabs) do
		local targetId = tab.id
		local selected = (tab.id == selectedId)
		local btn = bridge._symbolToggle(
			tab.symbol,
			tab.tooltip or tab.title or tab.id,
			selected and true or false,
			function(_)
				handleSelect(targetId)
			end)
		btn.fixedWidth = NAV.buttonSize
		btn.fixedHeight = NAV.buttonSize
		btn.flexGrow = 0
		btn.flexShrink = 0
		btn.accessibilityLabel = tab.tooltip or tab.title or tab.id
		buttons[tab.id] = btn
	end

	local children = {}
	for i = 1, #tabs do
		children[#children + 1] = buttons[tabs[i].id]
	end

	local bar = ns.HStack {
		fixedHeight = NAV.buttonSize,
		flexGrow = 0,
		flexShrink = 0,
		spacing = NAV.spacing,
		paddingHorizontal = NAV.paddingHorizontal,
		table.unpack(children),
	}

	local function select(id)
		handleSelect(id)
	end

	return bar, buttons, select
end

return NavigatorTabBar
