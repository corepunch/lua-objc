local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local VolumeContents = require("apps.diskmap.models.VolumeContents")
local Controller = {}; Controller.__index = Controller

-- One watched location, opened from its sidebar row: its size, the change
-- since the previous session and what it holds one level down. A category
-- lists its locations; a folder is measured when the page opens, unless the
-- scan already broke it down. `handlers.open(id)` opens a category sheet
-- and `handlers.closed()` leaves the page after Stop Watching.
function Controller.new(model, service, watchlist, actions, handlers)
	return setmetatable({model = model, service = service, watchlist = watchlist, actions = actions,
		handlers = handlers, generation = 0}, Controller)
end

function Controller:focus(key)
	if self.key ~= key then self.analyzed = nil end
	self.key = key
end

function Controller:row()
	for _, row in ipairs(self.watchlist:rows()) do
		if row.key == self.key then return row end
	end
end

function Controller:mount(host)
	self.generation = self.generation + 1
	self.template = Template.new(host, "apps/diskmap/views/Watched.etlua", ns)
	self:render()
	self:analyze()
	return self.refs
end

local function tilde(path, home)
	if path and home ~= "" and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
	return path
end

-- The resource whose category sheet the page's Open button shows: a group
-- itself, or a leaf's parent.
function Controller:category(row)
	local resource = row.resourceId and self.model.resources:find(row.resourceId)
	if not resource then return nil end
	return resource:isLeaf() and resource:getParent() or resource
end

function Controller:group(row)
	local resource = row.resourceId and self.model.resources:find(row.resourceId)
	return resource and not resource:isLeaf() and resource or nil
end

function Controller:render()
	local row = self:row()
	if not row or not self.template then return end
	local summary = {row.size, row.changeText}
	if row.path then table.insert(summary, tilde(row.path, self.model.home)) end
	local buttons = {}
	if row.path and not row.missing then table.insert(buttons, {id = "reveal", title = "Show in Finder", action = "reveal"}) end
	local category = self:category(row)
	if category then table.insert(buttons, {id = "openCategory", title = "Open " .. category.name .. "…", action = "openCategory"}) end
	table.insert(buttons, {id = "unwatch", title = "Stop Watching", systemImage = "eye.slash", action = "unwatch"})
	local _, refs = self.template:update({watched = row, summary = table.concat(summary, " · "), buttons = buttons,
		contents = not row.missing and (self:group(row) or row.path) and self:contentsDetail() or nil,
		-- A category's locations differ by policy; a folder's children are
		-- already labeled Folder or File under their names.
		detailColumn = self:group(row) ~= nil,
		actions = {
			reveal = function() self.service.reveal(row.path) end,
			openCategory = function() self.handlers.open(category.id) end,
			unwatch = function()
				local entry = self.watchlist:find(row.key)
				if entry and self.watchlist:toggle(entry) then self.handlers.closed() end
			end,
			contentsMenu = function(_, _, item) return self:contentsMenu(item) end,
			openContents = function(_, _, item)
				if not item then return end
				local resource = item.resourceId and self.model.resources:find(item.resourceId)
				if resource then self.handlers.open(resource.id)
				else self.service.reveal(item.path) end
			end,
		}})
	self.refs = refs
	if refs.contents then refs.contents:replaceRows(self:contents()) end
end

function Controller:contents()
	local row = self:row()
	local group = row and self:group(row)
	if group then
		local rows = Categories.rows(self.model, group.id)
		for _, item in ipairs(rows) do item.resourceId, item.detail = item.id, item.policy or "" end
		return self.actions:annotate(rows)
	end
	local rows = VolumeContents.rows(row and row.path or "", self.analyzed and self.analyzed.entries)
	return self.actions:annotate(rows)
end

function Controller:contentsDetail()
	local row = self:row()
	local group = row and self:group(row)
	if group then return Model.plural(#group:getChildren(), "location") .. " Diskmap measures here. Open one to review it." end
	local analyzed = self.analyzed
	if not analyzed or analyzed.loading then return "Measuring…" end
	if analyzed.failure then return analyzed.failure end
	local rows, total = VolumeContents.rows(row.path, analyzed.entries)
	return Model.size(total) .. " in " .. Model.plural(#rows, "item") .. " at the top level."
end

-- A folder's immediate children: the scan's breakdown when it made one,
-- otherwise a measurement of this folder alone.
function Controller:analyze()
	local row = self:row()
	if not row or row.missing or not row.path or self:group(row) or self.analyzed then return end
	local breakdown = row.resourceId and self.model.breakdowns[row.resourceId]
	if breakdown then self.analyzed = {entries = breakdown}; self:render(); return end
	local analyze = rawget(self.service, "analyzeFolder")
	if not analyze then return end
	self.analyzed = {loading = true}
	self:render()
	local generation, key = self.generation, self.key
	analyze(row.path, function(entries, failure)
		if generation ~= self.generation or key ~= self.key then return end
		self.analyzed = {entries = entries or {}, failure = failure}
		self:render()
	end)
end

function Controller:contentsMenu(item)
	if not item then return {} end
	if item.resourceId then return self.actions:resource(item.resourceId) end
	return self.actions:folder(item)
end

function Controller:update()
	self:render()
end

function Controller:dispose()
	self.generation = self.generation + 1
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
