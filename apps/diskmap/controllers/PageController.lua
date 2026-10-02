local ns = require("AppKit")
local Template = require("ui.template")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local Selection = require("apps.diskmap.models.Selection")
local Page = {}; Page.__index = Page

local VIEWS = "apps/diskmap/views/"

-- One lifecycle for every sidebar page, and one controller for every page
-- that is only data. A page is a table:
--
--   id         the sidebar destination: its icon, color and title head the page
--   view       the template in views/; Page.etlua, the list page, when omitted
--   layout     what Page.etlua lays out: tiles, sections of lists, a footnote
--              (the fields are listed in the template). A function
--              `layout(presented)` when the structure depends on the data.
--   children   {ref = template}: retained child templates mounted in a ref
--   present(model, state) → {
--     lists      {ref = rows}: rows for each list
--     texts      {ref = text}
--     hidden     {ref = boolean}
--     children   {ref = data} for each child template
--     links      {action = {open = id} | {page = id, filter = n} | {settings = section}}
--   }
--
-- Behaviour is the same on every such page: a row's menu is its resource's
-- menu, and opening a row goes where Destinations sends that resource. A row
-- that stands for another page (`row.page`) opens that page.
-- `handlers.open(id)` opens a resource, `handlers.show(page, filter)` a
-- sidebar page and `handlers.settings(section)` System Settings; `actions`
-- builds row menus.
--
-- A page with behaviour of its own (it reads a folder, runs a search, keeps
-- a filter) is a class from `Page.extend(id, view)`: it inherits `attach`,
-- `render` and `dispose`, and supplies `mount` and `update`.
function Page.new(context, entry)
	local page = require("apps.diskmap.models." .. entry.attrs.source).page(context, entry)
	return setmetatable({model = context.model, actions = context.actions, page = page, id = page.id, view = page.view,
		handlers = {open = context.open, show = context.showFiltered,
			settings = function(section) context.service.openSettings(section) end}}, Page)
end

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

function Page:menu(row)
	if row.page then
		return {{title = "Open " .. (row.pageName or "Page"), systemImage = "arrow.right.circle",
			action = function() self.handlers.show(row.page, row.filter) end}}
	end
	return self.actions:resource(row.id)
end

function Page:activate(row)
	if not row then return end
	if row.page then self.handlers.show(row.page, row.filter) else self.handlers.open(row.id) end
end

-- A selected row gets a full, wrapping explanation and an explicit route
-- to its detail page. Selection survives live measurements by resource id.
-- With nothing selected the panel is hidden: an empty inspector would only
-- push the suggestions out of a small window.
function Page:showDetails()
	if not self.page.details or not self.template then return end
	if self.refs and self.refs.selectionDetails then self.refs.selectionDetails.hidden = self.selectedRow == nil end
	if not self.selectedRow then return end
	self.detailsTemplate = self.detailsTemplate or self.template:child("selectionDetails", VIEWS .. "SelectionDetails.etlua")
	local details = self.page.details(self.model, self.selectedRow)
	details.actions = {openSelection = function() self:activate(self.selectedRow) end}
	self.detailsTemplate:update(details)
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

function Page:follow(link)
	if link.open then self.handlers.open(link.open)
	elseif link.page then self.handlers.show(link.page, link.filter)
	elseif link.settings then self.handlers.settings(link.settings) end
end

-- The template carries only structure, so scan progress updates rows and
-- labels in place instead of rebuilding the page under the reader.
function Page:update(state)
	if not self.template then return end
	local page = self.page
	local presented = page.present(self.model, state or {})
	local actions = {
		rowMenu = function(_, _, row) return self:menu(row) end,
		open = function(_, _, row) self:activate(row) end,
		select = function(_, _, row)
			if self.updating then return end
			self.selectedRow, self.selectedId = row, row and row.id
			self.updating = true
			for id, rows in pairs(self.listRows or {}) do Selection.show(self.refs[id], rows, self.selectedId) end
			self.updating = false
			self:showDetails()
		end,
	}
	for name, link in pairs(presented.links or {}) do actions[name] = function() self:follow(link) end end
	local layout = page.layout
	if type(layout) == "function" then layout = layout(presented) end
	local refs = self:render({layout = layout, actions = actions})
	self.listRows = presented.lists
	self.updating, self.selectedRow = true, nil
	for id, rows in pairs(presented.lists or {}) do
		refs[id]:replaceRows(rows)
		if page.details then
			local index = Selection.index(rows, self.selectedId)
			if index then self.selectedRow = rows[index + 1] end
			Selection.show(refs[id], rows, self.selectedId)
		end
	end
	self.updating = false
	if not self.selectedRow then self.selectedId = nil end
	self:showDetails()
	for id, text in pairs(presented.texts or {}) do refs[id].text = text end
	for id, hidden in pairs(presented.hidden or {}) do refs[id].hidden = hidden end
	for id, view in pairs(page.children or {}) do
		self.children[id] = self.children[id] or self.template:child(id, VIEWS .. view .. ".etlua")
		local childData = presented.children and presented.children[id] or {}
		childData.actions = actions
		self.children[id]:update(childData)
	end
end

return Page
