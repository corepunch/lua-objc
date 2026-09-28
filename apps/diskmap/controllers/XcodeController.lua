local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Xcode = require("apps.diskmap.models.Xcode")
local Status = require("apps.diskmap.models.Status")
local Controller = {}; Controller.__index = Controller

-- Three reviewable lists, in the order they are usually worth cleaning.
local SECTIONS = {
	{id = "support", title = "Device Support", status = true, icon = "iphone.gen3", color = "systemBlue",
		detail = "Symbols Xcode copies from each device OS version you debug. The newest version per platform is kept.",
		bulkTitle = "Mark Older Versions", bulkHelp = "Mark every version except the newest per platform",
		consequence = "Debug symbols for one OS version. Xcode copies them again the next time you debug a device running it."},
	{id = "derived", title = "DerivedData", status = true, icon = "hammer", color = "systemOrange",
		detail = "Build products and indexes per project. Folders whose project no longer exists come first; caches shared by every project come last.",
		bulkTitle = "Mark Missing Projects", bulkHelp = "Mark build data of projects that no longer exist",
		consequence = "Build products and the code index. The next build and indexing of this project take longer."},
	{id = "archives", title = "Archives", detailColumn = true, icon = "archivebox", color = "systemPurple",
		detail = "Shipped builds with their debug symbols, oldest first. Keep archives for versions people still run.",
		consequence = "A shipped build and its dSYMs. Without it, crash reports for this version cannot be symbolicated."},
}

-- Row statuses as Status symbols: the newest device support stays (red);
-- build data of a missing project is safe to remove (green); older versions
-- and build data of a present or unknown project need a look (orange).
-- Caches shared by every project are rebuilt by Xcode (green).
local STATUS = {["Newest · keep"] = "Keep", Older = "Review", Missing = "Rebuildable", Present = "Review", Unknown = "Review",
	Shared = "Rebuildable"}
Controller.statuses = STATUS

-- The Xcode page: device support per OS version, DerivedData per project and
-- archives, read from Xcode's folders when the page opens. Rows are marked
-- for cleanup from their menu; nothing is removed here.
function Controller.new(model, service, actions)
	return setmetatable({model = model, service = service, actions = actions, generation = 0, rows = {}}, Controller)
end

function Controller:item(section, row)
	return {path = row.path, name = row.name .. (row.subtitle ~= "" and (" · " .. row.subtitle) or ""), bytes = row.bytes,
		source = "Xcode · " .. section.title, consequence = section.consequence}
end

local function bulkable(section, row)
	if section.id == "support" then return not row.keep end
	if section.id == "derived" then return row.missing end
	return false
end

function Controller:mount(host, state)
	self.generation = self.generation + 1
	self.query = state.query or ""
	self.template = Template.new(host, "apps/diskmap/views/Xcode.etlua", ns)
	local actions = {openXcode = function() self.service.openOwner("xcode") end}
	for _, section in ipairs(SECTIONS) do
		local id = section.id
		actions["menu_" .. id] = function(_, _, row)
			return self.actions:folder(row, nil, self:item(section, row))
		end
		actions["reveal_" .. id] = function(_, _, row) if row then self.service.reveal(row.path) end end
		actions["bulk_" .. id] = function()
			local items = {}
			for _, row in ipairs(self.rows[id] or {}) do
				if bulkable(section, row) then table.insert(items, self:item(section, row)) end
			end
			self.actions:markAll(items)
		end
	end
	local _, refs = self.template:update({sections = SECTIONS, actions = actions})
	self.refs = refs
	self:load()
	return refs
end

local function filtered(rows, query)
	local needle, kept = (query or ""):lower(), {}
	for _, row in ipairs(rows or {}) do
		if needle == "" or (row.name .. " " .. (row.subtitle or "") .. " " .. row.path):lower():find(needle, 1, true) then
			local copy = {}
			for key, value in pairs(row) do copy[key] = value end
			table.insert(kept, copy)
		end
	end
	return kept
end

function Controller:show()
	if not self.refs then return end
	local total = 0
	for _, section in ipairs(SECTIONS) do
		local rows = self.actions:annotate(filtered(self.rows[section.id], self.query), section.icon, section.color)
		for _, row in ipairs(rows) do
			if section.status then
				row.detail = row.status
				Status.apply(row, STATUS[row.status])
			else
				row.detail = row.date ~= "" and row.date or "—"
			end
			row.calculating = row.bytes == nil and self.measuring == true
		end
		self.refs["list_" .. section.id]:replaceRows(rows)
		total = total + Xcode.total(self.rows[section.id])
		self.refs[section.id .. "Section"].hidden = not self.loading and #(self.rows[section.id] or {}) == 0
		local bulk = self.refs["bulk_" .. section.id]
		if bulk then
			local pending = false
			for _, row in ipairs(self.rows[section.id] or {}) do
				if bulkable(section, row) and not self.actions:isMarked(row.path) then pending = true end
			end
			bulk.enabled = pending
		end
	end
	self.refs.xcodeSummary.text = self.loading and "Reading Xcode's device support, build data and archives…"
		or total == 0 and "No Xcode device support, build data or archives on this Mac."
		or (Model.size(total) .. " in device support, build data and archives")
end

function Controller:marksChanged() self:show() end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

local function children(service, path)
	return type(service.children) == "function" and service.children(path) or {}
end

function Controller:load()
	self.loading = true
	self:show()
	local service, generation = self.service, self.generation
	local support, derived, archives = {}, {}, {}
	for _, root in ipairs(Xcode.deviceSupport) do
		for _, child in ipairs(children(service, root.path)) do
			table.insert(support, {platform = root.platform, name = child.name, path = child.path, bytes = child.bytes})
		end
	end
	for _, child in ipairs(children(service, Xcode.derivedData)) do
		local plist = service.readPropertyList and service.readPropertyList(child.path .. "/info.plist") or nil
		local workspace = type(plist) == "table" and plist.WorkspacePath or nil
		local exists
		if workspace and type(service.exists) == "function" then exists = service.exists(workspace) == true end
		table.insert(derived, {name = child.name, path = child.path, bytes = child.bytes, workspace = workspace, exists = exists})
	end
	for _, day in ipairs(children(service, Xcode.archives)) do
		for _, archive in ipairs(children(service, day.path)) do
			if archive.name:match("%.xcarchive$") then
				table.insert(archives, {name = archive.name, path = archive.path, bytes = archive.bytes, date = day.name,
					plist = service.readPropertyList and service.readPropertyList(archive.path .. "/Info.plist") or nil})
			end
		end
	end
	local function build()
		self.rows = {support = Xcode.supportRows(support), derived = Xcode.derivedRows(derived), archives = Xcode.archiveRows(archives)}
	end
	build()
	self.loading = false
	local pending, paths = {}, {}
	for _, list in ipairs({support, derived, archives}) do
		for _, entry in ipairs(list) do
			if entry.bytes == nil then table.insert(paths, entry.path); table.insert(pending, entry) end
		end
	end
	if #paths == 0 or type(service.measure) ~= "function" then self:show(); return end
	self.measuring = true
	self:show()
	service.measure(paths, function(sizes)
		if generation ~= self.generation then return end
		for index, entry in ipairs(pending) do entry.bytes = sizes[index] or 0 end
		self.measuring = false
		build()
		self:show()
	end)
end

function Controller:badge()
	if self.loading or self.measuring or not self.rows.support then return nil end
	local total = Xcode.total(self.rows.support) + Xcode.total(self.rows.derived) + Xcode.total(self.rows.archives)
	return total > 0 and Model.size(total) or nil
end

function Controller:dispose()
	self.generation = self.generation + 1
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
