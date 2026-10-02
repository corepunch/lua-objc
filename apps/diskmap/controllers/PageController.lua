local ns = require("AppKit")
local Template = require("ui.template")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local Page = {}; Page.__index = Page

local VIEWS = "apps/diskmap/views/"

-- The base of the pages that have behaviour of their own (they read a
-- folder, run a search, keep a filter): a class from `Page.extend(id, view)`
-- inherits `attach`, `render` and `dispose`, and supplies `mount` and
-- `update`. Pages that only rank storage in lists are models now
-- (models/ListPage.lua) drawn by the framework's page controller.
function Page.extend(id, view)
	local class = setmetatable({id = id, view = view}, Page)
	class.__index = class
	return class
end

-- Mounts the page's template into `host` with its first data. Work started
-- for an earlier visit compares `self.generation` to know it is stale.
function Page:attach(host, data)
	self.generation = (self.generation or 0) + 1
	self.template = Template.new(host, VIEWS .. (self.view or "Page") .. ".etlua", ns)
	return data and self:render(data)
end

-- Renders `data`; the template reconciles, so unchanged data costs nothing.
-- The header comes from the page's sidebar row unless the data names one.
function Page:render(data)
	data.header = data.header or Navigation.page(self.id)
	local _, refs = self.template:update(data)
	self.refs = refs
	return refs
end

function Page:dispose()
	self.generation = (self.generation or 0) + 1
	if self.template then self.template:dispose() end
	self.listRows = nil
	self.template, self.refs, self.children, self.detailsTemplate, self.selectedRow, self.selectedId = nil, nil, nil, nil, nil, nil
	self.decisions = nil
end

function Page:mount(host, state)
	self:attach(host)
	self.children = {}
	self:update(state)
	return self.refs
end

-- The page's leading decision (Decision.etlua) in the `host` ref, rendered
-- from `data` and reconciled like any child template. Returns its refs.
function Page:decision(host, data)
	if not self.template or not self.refs or not self.refs[host] then return nil end
	self.decisions = self.decisions or {}
	self.decisions[host] = self.decisions[host] or self.template:child(host, VIEWS .. "Decision.etlua")
	local _, refs = self.decisions[host]:update(data)
	return refs
end

return Page
