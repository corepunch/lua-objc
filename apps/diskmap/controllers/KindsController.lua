local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Selection = require("apps.diskmap.models.Selection")
local Scope = require("apps.diskmap.models.Scope")
local Sectors = require("ui.sectors")
local Controller = Page.extend("kinds", "Kinds")

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. `showFiles(kindId)` opens Large
-- Files narrowed to one kind; `show(page, filterName)` opens a page, Large
-- Files on one of its filters.
function Controller.new(model, showFiles, show)
	return setmetatable({model = model, showFiles = showFiles, show = show}, Controller)
end

-- The leading decision: the files of yours this page can point at, never a
-- kind's whole inventory. Disk images share an extension with system and
-- app images, so only the user-owned subset is offered.
function Controller:decisionData(kinds)
	local data = {id = "decision", icon = "opticaldiscdrive.fill", color = "systemTeal"}
	if #kinds == 0 then
		data.title, data.detail, data.amount, data.amountCaption = "Measuring files…", "Review candidates appear when the scan finishes.", "—", "could recover"
		return data
	end
	local installers = Files.rows(self.model, "Installers & archives")
	local removable = 0
	for _, row in ipairs(installers) do removable = removable + row.bytes end
	local inventory = 0
	for _, kind in ipairs(kinds) do if kind.id == "installers" or kind.id == "archives" then inventory = inventory + kind.bytes end end
	if removable > 0 then
		data.title = "Review " .. (#installers == 1 and "1 installer or archive" or (#installers .. " installers and archives")) .. " in your folders"
		data.detail = "Disk images, installers and archives total " .. Model.size(inventory) .. " stored; " .. Model.size(removable)
			.. " of them are in your own folders. The other " .. Model.size(math.max(0, inventory - removable)) .. " belong to the system and to apps, which manage them."
		data.amount, data.amountCaption = Model.size(removable), "could recover"
		data.actionTitle, data.action = "Show Installers", "decisionInstallers"
		return data
	end
	local files = Files.summary(self.model)
	if files and files.reviewableOld > 0 then
		data.icon, data.color = "clock.fill", "systemOrange"
		data.title = "Review " .. Model.plural(files.reviewableOld, "file") .. " of yours unused for a year"
		data.detail = "No installer or archive in your folders is large enough to list. These files were not opened or changed in a year; they may be your only copy."
		data.amount, data.amountCaption = Model.size(files.reviewableOldBytes), "to review"
		data.actionTitle, data.action = "Show Unused Files", "decisionOld"
		return data
	end
	data.icon, data.color = "checkmark.circle.fill", "systemGreen"
	data.title = "No large file of yours to review"
	data.detail = "Every large file belongs to an app, a library or the system. Clean Up lists the places their owners can clear."
	data.amount, data.amountCaption = Model.size(0), "could recover"
	data.actionTitle, data.action = "Open Clean Up", "decisionCleanup"
	return data
end

function Controller:mount(host, state)
	self:attach(host)
	self:update(state)
	return self.refs
end

function Controller:menu(row)
	local kindId = row.kindId or row.id
	local kind = Files.kindById(kindId)
	return {{title = "Show Largest " .. (kind and kind.name or "Files"), systemImage = "doc.fill", action = function() self.showFiles(kindId) end}}
end

-- The chart and headline re-render only when the set of kinds or the
-- selected kind changes; list rows update in place. The selected kind is the
-- page's selection token: its sector, its row, the headline and the top
-- extensions all name it.
function Controller:update(state)
	if not self.template then return end
	local kinds, extensions = Files.kinds(self.model)
	if not Selection.index(kinds, self.selectedId) then self.selectedId = nil end
	local all = 0
	for _, kind in ipairs(kinds) do all = all + kind.bytes end
	local marks, labels = {}, {}
	for _, kind in ipairs(kinds) do
		table.insert(marks, {id = kind.id, name = kind.name, color = kind.color, bytes = kind.bytes})
		table.insert(labels, kind.name .. " " .. kind.size)
	end
	-- The headline names the selected kind, or else the largest kind a
	-- person can act on; "Other files" and databases belong to apps.
	local headline
	for _, kind in ipairs(kinds) do
		if kind.id == self.selectedId then headline = kind; break end
	end
	if not headline then
		for _, kind in ipairs(kinds) do
			if kind.id ~= "other" and kind.id ~= "databases" then headline = kind; break end
		end
	end
	headline = headline or kinds[1]
	local actions = {
		kindMenu = function(_, _, row) return self:menu(row) end,
		openKind = function(_, _, row) if row then self.showFiles(row.kindId or row.id) end end,
		-- A row the pointer selected through its sector is only pointed at.
		selectKind = function(_, _, row) if row and not self.pointing then self:select(row.id) end end,
		-- The pointer over a sector points at its row; a click keeps the
		-- kind, and a click on the kind already kept opens its largest files.
		-- Leaving the chart returns to the kind that was kept.
		chartHover = function(id)
			if not self.refs then return end
			self.pointing = true
			Selection.show(self.refs.kinds, self.kinds, id or self.selectedId)
			self.pointing = false
			if not id and self.refs.kindsChart then Sectors.highlight(self.refs.kindsChart, self.selectedId) end
		end,
		chartSelect = function(id)
			if id == self.selectedId then self.showFiles(id) else self:select(id) end
		end,
	}
	for _, kind in ipairs(kinds) do actions["kind_" .. kind.id] = function() self.showFiles(kind.id) end end
	local selected = self.selectedId and headline or nil
	actions.decisionInstallers = function() if self.show then self.show("files", "Installers & archives") end end
	actions.decisionOld = function() if self.show then self.show("files", "Unused for a year") end end
	actions.decisionCleanup = function() if self.show then self.show("cleanup") end end
	-- The installers kind is an inventory: its headline states the total and
	-- the user-owned part apart, in the prominent text, never only in a row.
	local advice = headline and headline.advice
	if headline and headline.removableBytes then
		advice = (headline.removableBytes > 0
			and (Model.size(headline.removableBytes) .. " of it is in your own folders and can be reviewed; the rest belongs to the system and to apps, which manage it. ")
			or "None of it is in your own folders: it belongs to the system and to apps, which manage it. ") .. advice
	end
	local refs = self:render({kinds = marks, total = Model.size(all), scope = Scope.text(self.model, "kinds"),
		summary = #kinds == 0 and "Measuring files…" or (Model.size(all) .. " in files across " .. #kinds .. " kinds"),
		accessibilityLabel = "File types: " .. table.concat(labels, ", "),
		headline = headline and {id = headline.id, title = headline.name .. " · " .. headline.size .. " stored", advice = advice} or {},
		decision = self:decisionData(kinds),
		extensionsDetail = selected and ("The " .. selected.name .. " extensions that use the most space")
			or "The twelve extensions that use the most space",
		actions = actions})
	self.kinds = kinds
	for _, kind in ipairs(kinds) do kind.detail = Model.count(kind.count) end
	refs.kinds:replaceRows(kinds)
	for _, row in ipairs(extensions) do row.detail = Model.count(row.count) end
	refs.extensions:replaceRows(Selection.extensions(extensions, self.selectedId))
	-- Reloading rows drops the native selection; the token restores it.
	Selection.show(refs.kinds, kinds, self.selectedId)
	if refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
end

-- Keeps `id` as the selected kind: the headline and the top extensions
-- follow it, and its sector stays highlighted.
function Controller:select(id)
	id = Selection.index(self.kinds, id) and id or nil
	if self.selectedId == id then return end
	self.selectedId = id
	self:update()
end

return Controller
