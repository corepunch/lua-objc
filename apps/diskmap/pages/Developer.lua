local Inventories = require("apps.diskmap.models.Inventories")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Status = require("apps.diskmap.helpers.Status")
local Workflows = require("apps.diskmap.models.Workflows")
local Xcode = require("apps.diskmap.helpers.Xcode")

-- The Developer and Creative pages: one route for every kind of work, and Xcode.
local routes = {}

-- The pages of every kind of work (knowledge/Workflows.lua): Developer
-- tools, Music Production, Video Production and the rest are one route, and
-- each page names its work in app.xml (`workflow="music"`).
routes.workflow = ListRoute.extend({
	before = function(self) self.workflow = Workflows:find(self.params.workflow) end,
	-- The sections change with what was measured, so the layout follows the data.
	layout = function(_, presented) return presented.layout end,
})

function routes.workflow:present()
	local workflow = self.workflow
	local links, buttons = {}, {}
	for index, link in ipairs(workflow.links or {}) do
		links["link_" .. index] = link.page and {page = link.page} or {open = link.open}
		table.insert(buttons, {id = "link_" .. index, title = link.title, action = "link_" .. index})
	end
	local data = workflow:presentation()
	local structure, lists, texts = {}, {}, {}
	for _, section in ipairs(data.sections) do
		table.insert(structure, {id = "section_" .. section.id, title = section.title, detail = section.detail, sizeId = "size_" .. section.id,
			list = {id = "list_" .. section.id, menu = "rowMenu", activate = "open", status = true}})
		lists["list_" .. section.id] = section.rows
		texts["size_" .. section.id] = section.size
	end
	local subtitle = data.calculating and ("Measuring " .. workflow.noun .. "…")
		or (data.total .. " " .. workflow.summary
			.. (data.rebuildable > 0 and (" · " .. data.rebuildableSize .. " rebuildable now") or ""))
	return {layout = {buttons = buttons, sections = structure, scopeNote = workflow.id == "developer" and "Developer tools includes Xcode, package managers, containers and AI tools. Overview’s Developer category covers a different set by owner; these totals overlap." or nil, footnote = {text = workflow.footnote},
			empty = #structure == 0 and {id = "workflowEmpty", systemImage = self.params.icon, description = workflow.empty,
				title = data.calculating and ("Measuring " .. workflow.noun .. "…") or ("No " .. workflow.noun .. " found")} or nil},
		lists = lists, texts = texts, links = links, subtitle = subtitle}
end

local SECTIONS, STATUS = Xcode.sections, Xcode.statuses

local LAYOUT = {
	subtitle = "Reading Xcode's device support, build data and archives…",
	buttons = {{id = "openOrganizer", title = "Open Xcode", action = "openXcode", help = "Manage archives in Xcode's Organizer"}},
	sections = {},
}
for _, section in ipairs(SECTIONS) do
	table.insert(LAYOUT.sections, {id = section.id .. "Section", title = section.title, detail = section.detail,
		buttons = section.bulkTitle and {{id = "bulk_" .. section.id, title = section.bulkTitle, systemImage = "plus.circle",
			action = "bulk_" .. section.id, help = section.bulkHelp}},
		list = {id = "list_" .. section.id, menu = "rowMenu", activate = "reveal",
			status = section.status, detailColumn = section.detailColumn}})
end

-- The Xcode page: device support per OS version, DerivedData per project and
-- archives, read from Xcode's folders when the page opens. Rows are marked
-- for cleanup from their menu; nothing is removed here.
routes.xcode = ListRoute.extend({layout = LAYOUT, statuses = STATUS,
	openXcode = function(page)
		local ok, message = page.app.service.openOwner("xcode")
		if ok == false then page.app.service.showError("Cannot open Xcode", message) end
	end,
	-- The sidebar's badge: what the page found, once it has read.
	init = function(page) ListRoute.init(page); page.stock = Inventories:state("xcode") end,
	load = function(page) page.app.inventories:load("xcode") end,
	menu = function(page, row)
		for _, section in ipairs(SECTIONS) do
			if section.id == row.section then return page.rowActions:folder(row, nil, Xcode.item(section, row)) end
		end
	end,
	present = function(page)
		if not page.stock.loaded then return {computing = "Reading Xcode's device support, build data and archives…"} end
		local lists, hidden, disabled, total = {}, {}, {}, 0
		for _, section in ipairs(SECTIONS) do
			local rows = Xcode.copies(page.stock.rows[section.id])
			for _, row in ipairs(rows) do
				row.section = section.id
				row.source, row.consequence = "Xcode · " .. section.title, section.consequence
				if section.status then
					row.detail = row.status
					Status.apply(row, STATUS[row.status])
				else
					row.detail = row.date ~= "" and row.date or "—"
				end
			end
			lists["list_" .. section.id] = page.rowActions:annotate(rows, section.icon, section.color)
			total = total + Xcode.total(page.stock.rows[section.id])
			hidden[section.id .. "Section"] = #page.stock.rows[section.id] == 0
			local pending = false
			for _, row in ipairs(rows) do
				if Xcode.bulkable(section, row) and not page.rowActions:isIncluded(row.path) then pending = true end
			end
			disabled["bulk_" .. section.id] = not pending
		end
		return {lists = lists, hidden = hidden, disabled = disabled, subtitle = total == 0
			and "No Xcode device support, build data or archives on this Mac."
			or (Format.size(total) .. " in device support, build data and archives")}
	end})
-- "Mark All" of each section marks its rows that can be marked.
for _, section in ipairs(SECTIONS) do
	routes.xcode["bulk_" .. section.id] = function(page)
		return page.rowActions:bulk(page.presented.lists["list_" .. section.id] or {},
			function(row) return Xcode.bulkable(section, row) end, function(row) return Xcode.item(section, row) end)
	end
end

return routes
