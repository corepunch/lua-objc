local ns = require("AppKit")
local bridge = require("bridge")

local TABS = {
	height = 34,
	controlHeight = 28,
	horizontalPadding = 6,
}

-- NavigatorTabBar: Xcode-style navigator tab strip backed by native
-- NSSegmentedControl with NSSegmentSwitchTrackingSelectOne (radio group).
-- Props: tabs (array of {id, symbol, tooltip}), selectedId, onSelect(id).
-- Returns the bar view and a select(id) helper.
local function NavigatorTabBar(props)
	props = props or {}
	local tabs = props.tabs or {}
	local selectedId = props.selectedId or (tabs[1] and tabs[1].id)
	local onSelect = props.onSelect

	local selectedIdx = 0
	local segments = {}
	for i, tab in ipairs(tabs) do
		if tab.id == selectedId then
			selectedIdx = i - 1
		end
		segments[#segments + 1] = {
			tab.symbol,
			tab.tooltip or tab.title or tab.id,
		}
	end

	local seg = bridge._segmentedControl(segments, selectedIdx,
		function(sender)
			local idx = sender.selectedSegment
			local tab = tabs[idx + 1]
			if tab and onSelect then
				onSelect(tab.id)
			end
		end)
	seg.fixedHeight = TABS.controlHeight
	seg.fillWidth = true
	seg.flexGrow = 1
	seg.flexShrink = 0

	local bar = ns.HStack {
		fixedHeight = TABS.height,
		flexGrow = 0,
		flexShrink = 0,
		paddingHorizontal = TABS.horizontalPadding,
		seg,
	}

	local function select(id)
		for i, tab in ipairs(tabs) do
			if tab.id == id then
				local idx = i - 1
				if idx >= 0 and idx < seg.segmentCount then
					seg.selectedSegment = idx
				end
				if onSelect then
					onSelect(tab.id)
				end
				return
			end
		end
	end

	return bar, select
end

return NavigatorTabBar
