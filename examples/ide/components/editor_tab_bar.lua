local ns = require("AppKit")
local bridge = require("bridge")

local TAB = {
	height = 28,
	maxWidth = 160,
	minWidth = 80,
}

local EditorTabBar = {}
EditorTabBar.__index = EditorTabBar

local function shortName(path)
	return path:match("([^/\\]+)$") or path
end

local function buildTabViews(self)
	bridge._clearContainer(self._strip)
	if not self._tabs or #self._tabs == 0 then
		bridge._add(self._strip, ns.Spacer())
		return
	end

	for i, tab in ipairs(self._tabs) do
		local tabId = tab.id
		local isActive = (tabId == self._activeId)
		local name = tab.title or shortName(tab.path)

		local tabBtn = ns.Button {
			title = name,
			style = isActive and "primary" or "plain",
			fixedHeight = TAB.height,
			maxWidth = TAB.maxWidth,
			minWidth = TAB.minWidth,
			flexGrow = 0,
			flexShrink = 0,
			action = function()
				self:switchToTab(tabId)
			end,
		}

		local closeBtn = ns.Button {
			title = "x",
			style = "plain",
			fixedWidth = 20,
			fixedHeight = TAB.height,
			flexGrow = 0,
			flexShrink = 0,
			action = function()
				self:removeTab(tabId)
			end,
		}

		local tabItem = ns.HStack {
			spacing = 0,
			alignment = "center",
			flexGrow = 0,
			flexShrink = 0,
			tabBtn,
			closeBtn,
		}
		bridge._add(self._strip, tabItem)
	end

	bridge._add(self._strip, ns.Spacer())
	if self._strip.superview then
		bridge._layout(self._strip.superview)
	end
end

function EditorTabBar:addTab(path, content)
	if not path then return end

	for _, tab in ipairs(self._tabs) do
		if tab.path == path then
			self:switchToTab(tab.id)
			return tab.id
		end
	end

	local tabId = path
	local tab = {
		id = tabId,
		path = path,
		title = shortName(path),
		content = content or "",
	}
	self._tabs[#self._tabs + 1] = tab

	self:_saveCurrentContent()
	self._activeId = tabId
	buildTabViews(self)

	if self._onTabChange then
		self._onTabChange(tabId, tab.content)
	end

	return tabId
end

function EditorTabBar:switchToTab(tabId)
	if tabId == self._activeId then return end

	self:_saveCurrentContent()

	self._activeId = tabId
	buildTabViews(self)

	local tab = self:_findActiveTab()
	if tab and self._onTabChange then
		self._onTabChange(tab.id, tab.content)
	end
end

function EditorTabBar:removeTab(tabId)
	local newTabs = {}
	local removedActive = (tabId == self._activeId)
	local newActiveId = nil

	for _, tab in ipairs(self._tabs) do
		if tab.id ~= tabId then
			newTabs[#newTabs + 1] = tab
			if removedActive and not newActiveId then
				newActiveId = tab.id
			end
		end
	end

	if #newTabs == 0 then
		self._tabs = {}
		self._activeId = nil
		buildTabViews(self)
		if self._onTabChange then
			self._onTabChange(nil, "")
		end
		return
	end

	self._tabs = newTabs
	if removedActive then
		self._activeId = newActiveId
		local tab = self:_findActiveTab()
		buildTabViews(self)
		if tab and self._onTabChange then
			self._onTabChange(tab.id, tab.content)
		end
		return
	end

	buildTabViews(self)
end

function EditorTabBar:saveCurrentContent(content)
	local tab = self:_findActiveTab()
	if tab then
		tab.content = content
	end
end

function EditorTabBar:_saveCurrentContent()
	if self._saveFn then
		local content = self._saveFn()
		local tab = self:_findActiveTab()
		if tab then
			tab.content = content
		end
	end
end

function EditorTabBar:getActiveTab()
	return self:_findActiveTab()
end

function EditorTabBar:_findActiveTab()
	if not self._activeId then return nil end
	for _, tab in ipairs(self._tabs) do
		if tab.id == self._activeId then
			return tab
		end
	end
	return nil
end

local function create(props)
	props = props or {}
	local self = setmetatable({
		_tabs = {},
		_activeId = nil,
		_onTabChange = props.onTabChange,
		_saveFn = props.saveFn,
	}, EditorTabBar)

	self._strip = ns.HStack {
		fixedHeight = TAB.height + 4,
		flexGrow = 0,
		flexShrink = 0,
		spacing = 2,
		paddingHorizontal = 4,
		paddingVertical = 2,
		alignment = "center",
	}

	return self
end

return create
