local Model = require("apps.diskmap.Model")
local ListPage = require("apps.diskmap.models.ListPage")
local Xcode = require("apps.diskmap.models.Xcode")
local Status = require("apps.diskmap.models.Status")

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

local LAYOUT = {
	summary = "Reading Xcode's device support, build data and archives…", summaryId = "xcodeSummary",
	buttons = {{id = "openOrganizer", title = "Open Xcode", action = "openXcode", help = "Manage archives in Xcode's Organizer"}},
	sections = {},
	footnote = {text = "Open a row's menu to mark it for cleanup. Marked items move to the Trash only after you review them in Marked Items."},
}
for _, section in ipairs(SECTIONS) do
	table.insert(LAYOUT.sections, {id = section.id .. "Section", title = section.title, detail = section.detail,
		buttons = section.bulkTitle and {{id = "bulk_" .. section.id, title = section.bulkTitle, systemImage = "plus.circle",
			action = "bulk_" .. section.id, help = section.bulkHelp}},
		list = {id = "list_" .. section.id, menu = "rowMenu", activate = "reveal",
			status = section.status, detailColumn = section.detailColumn}})
end

local function item(section, row)
	return {path = row.path, name = row.name .. (row.subtitle ~= "" and (" · " .. row.subtitle) or ""), bytes = row.bytes,
		source = "Xcode · " .. section.title, consequence = section.consequence}
end

local function bulkable(section, row)
	if section.id == "support" then return not row.keep end
	if section.id == "derived" then return row.missing end
	return false
end

local function children(service, path)
	return type(service.children) == "function" and service.children(path) or {}
end

-- Reads Xcode's folders and, for the entries the listing did not size,
-- asks the service to measure them. The page is drawn when both are done;
-- a visit that ended meanwhile bumps the generation and ignores the answer.
local function read(page)
	local service, services, generation = page.services.service, page.services, page.generation
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
		page.rows = {support = Xcode.supportRows(support), derived = Xcode.derivedRows(derived), archives = Xcode.archiveRows(archives)}
		page.reading = false
		services.refresh()
	end
	local pending, paths = {}, {}
	for _, list in ipairs({support, derived, archives}) do
		for _, entry in ipairs(list) do
			if entry.bytes == nil then table.insert(paths, entry.path); table.insert(pending, entry) end
		end
	end
	if #paths == 0 or type(service.measure) ~= "function" then
		for _, entry in ipairs(pending) do entry.bytes = 0 end
		return build()
	end
	service.measure(paths, function(sizes)
		if generation ~= page.generation then return end
		for index, entry in ipairs(pending) do entry.bytes = sizes[index] or 0 end
		build()
	end)
end

local function filtered(rows, query)
	local needle, kept = query:lower(), {}
	for _, row in ipairs(rows or {}) do
		if needle == "" or (row.name .. " " .. (row.subtitle or "") .. " " .. row.path):lower():find(needle, 1, true) then
			local copy = {}
			for key, value in pairs(row) do copy[key] = value end
			table.insert(kept, copy)
		end
	end
	return kept
end

-- The Xcode page: device support per OS version, DerivedData per project and
-- archives, read from Xcode's folders when the page opens. Rows are marked
-- for cleanup from their menu; nothing is removed here.
local class = ListPage.class(function()
	local actions = {
		openXcode = function(page)
			local ok, message = page.services.service.openOwner("xcode")
			if ok == false then page.services.service.showError("Cannot open Xcode", message) end
		end,
		-- The sidebar's badge: what the page found, once it has read.
		badge = function(page)
			if page.reading ~= false then return nil end
			local total = 0
			for _, section in ipairs(SECTIONS) do total = total + Xcode.total(page.rows[section.id]) end
			return total > 0 and Model.size(total) or nil
		end,
	}
	for _, section in ipairs(SECTIONS) do
		actions["bulk_" .. section.id] = function(page)
			local items = {}
			for _, row in ipairs(page.rows[section.id]) do
				if bulkable(section, row) then table.insert(items, item(section, row)) end
			end
			page.actions:markAll(items)
		end
	end
	return {id = "xcode", layout = LAYOUT, actions = actions,
	load = function(page) page.generation, page.reading = (page.generation or 0) + 1, true; read(page) end,
	unload = function(page) page.generation = page.generation + 1 end,
	menu = function(page, row)
		for _, section in ipairs(SECTIONS) do
			if section.id == row.section then return page.actions:folder(row, nil, item(section, row)) end
		end
	end,
	present = function(_, state, page)
		if page.reading ~= false then return {computing = "Reading Xcode's device support, build data and archives…"} end
		local lists, hidden, disabled, total = {}, {}, {}, 0
		for _, section in ipairs(SECTIONS) do
			local rows = filtered(page.rows[section.id], state.query or "")
			for _, row in ipairs(rows) do
				row.section = section.id
				if section.status then
					row.detail = row.status
					Status.apply(row, STATUS[row.status])
				else
					row.detail = row.date ~= "" and row.date or "—"
				end
			end
			lists["list_" .. section.id] = page.actions:annotate(rows, section.icon, section.color)
			total = total + Xcode.total(page.rows[section.id])
			hidden[section.id .. "Section"] = #page.rows[section.id] == 0
			local pending = false
			for _, row in ipairs(page.rows[section.id]) do
				if bulkable(section, row) and not page.actions:isIncluded(row.path) then pending = true end
			end
			disabled["bulk_" .. section.id] = not pending
		end
		return {lists = lists, hidden = hidden, disabled = disabled, texts = {xcodeSummary = total == 0
			and "No Xcode device support, build data or archives on this Mac."
			or (Model.size(total) .. " in device support, build data and archives")}}
	end}
end)
class.statuses = STATUS
return class
