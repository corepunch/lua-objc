local ns = require("AppKit")
local bridge = require("bridge")
local NavigatorTabBar = require("examples.ide.components.navigator_tab_bar")

local function wrapContent(view)
	if not view then return nil end
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- NavigatorArea: left sidebar panel with icon tabs.
-- New API: tabs (array of {id, symbol, tooltip}), content (table id→view),
--   selectedId, onSelect(id).
-- Legacy API: title (string), content (single view) — renders without tabs.
-- Mirrors Xcode's IDENavigatorArea with icon-based tab switching.
local function NavigatorArea(props)
	props = props or {}

	local contentType = type(props.content)
	if contentType == "userdata" or contentType == "nil" then
		-- Legacy single-content mode: ControlBar + content.
		local ControlBar = require("examples.ide.components.control_bar")
		return ns.VStack {
			spacing = 0,
			ControlBar { title = props.title },
			wrapContent(props.content),
		}
	end

	local tabs = props.tabs or {
		{ id = "files", symbol = "folder", tooltip = "Files" },
	}
	local content = props.content or {}
	local initialTab = props.selectedId or (tabs[1] and tabs[1].id)

	local bar, selectTab = NavigatorTabBar {
		tabs = tabs,
		selectedId = initialTab,
		onSelect = function(id)
			if content[id] then
				for tid, view in pairs(content) do
					view.hidden = (tid ~= id)
				end
			end
		end,
	}

	local children = { bar, ns.Separator() }
	for tid, view in pairs(content) do
		view.hidden = (tid ~= initialTab)
		children[#children + 1] = wrapContent(view)
	end

	local area = ns.VStack {
		spacing = 0,
		table.unpack(children),
	}

	return area
end

return NavigatorArea
