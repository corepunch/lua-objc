local commands = require("ui.commands")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local Controller = {}; Controller.__index = Controller

-- The menu bar: its actions and their validation. Window.etlua lays the
-- menus out; this controller supplies what they do. `handlers` come from
-- the root controller: `show(id, params)`, `destination()`, `measuring()`,
-- `refresh()`, `cancel()`, `history()`, `openFolder()`,
-- `quickLook()`/`canQuickLook()` and `navigation`, the back/forward history.
function Controller.new(service, handlers)
	return setmetatable({service = service, handlers = handlers}, Controller)
end

function Controller:actions()
	local h = self.handlers
	local actions = {
		refresh = h.refresh,
		canRefresh = function() return not h.measuring() end,
		cancel = h.cancel,
		canCancel = function() return h.measuring() end,
		storageSettings = function() self.service.openSettings() end,
		privacy = function() self.service.openSettings("privacy") end,
		back = function() h.navigation:back() end,
		canGoBack = function() return h.navigation:canGoBack() end,
		forward = function() h.navigation:forward() end,
		canGoForward = function() return h.navigation:canGoForward() end,
		history = h.history,
		openFolder = h.openFolder,
		quickLook = h.quickLook,
		canQuickLook = function() return h.canQuickLook() end,
	}
	for _, page in ipairs(Navigation.destinations) do
		if page.id then
			actions["page_" .. page.id] = function() h.show(page.id) end
			actions["isPage_" .. page.id] = function() return true, h.destination() == page.id end
		end
	end
	return actions
end

-- Template data for the menus: sidebar pages grouped by section for the Go menu.
function Controller:data()
	local sections, current = {}, nil
	for _, page in ipairs(Navigation.destinations) do
		if page.section or not current then
			current = {title = page.title, pages = {}}
			table.insert(sections, current)
		end
		if not page.section then table.insert(current.pages, page) end
	end
	return {sections = sections}
end

-- Every keyboard shortcut in the installed menu bar as `{title, key, modifiers}`.
function Controller:shortcuts(spec)
	local built = commands.build(spec)
	local list = {}
	local function walk(items, path)
		for _, item in ipairs(items) do
			if item.items then walk(item.items, path .. " › " .. item.title)
			elseif not item.separator and (item.keyEquivalent or "") ~= "" then
				table.insert(list, {title = path .. " › " .. item.title, key = item.keyEquivalent, modifiers = item.modifiers})
			end
		end
	end
	for _, menu in ipairs(built.menus) do walk(menu.items, menu.title) end
	return list
end

return Controller
