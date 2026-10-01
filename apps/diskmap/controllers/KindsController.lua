local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Selection = require("apps.diskmap.models.Selection")
local Scope = require("apps.diskmap.models.Scope")
local Sectors = require("ui.sectors")
local Controller = Page.extend("kinds", "Kinds")

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. `showFiles(kindId)` opens Large
-- Files narrowed to one kind.
function Controller.new(model, showFiles)
	return setmetatable({model = model, showFiles = showFiles}, Controller)
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
	local refs = self:render({kinds = marks, total = Model.size(all), scope = Scope.text(self.model, "kinds"),
		summary = #kinds == 0 and "Measuring files…" or (Model.size(all) .. " in files across " .. #kinds .. " kinds"),
		accessibilityLabel = "File types: " .. table.concat(labels, ", "),
		headline = headline and {id = headline.id, title = headline.name .. " · " .. headline.size, advice = headline.advice} or {},
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
