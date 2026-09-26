local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Controller = {}; Controller.__index = Controller

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. `showFiles(kindId)` opens Large
-- Files narrowed to one kind.
function Controller.new(model, showFiles)
	return setmetatable({model = model, showFiles = showFiles}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Kinds.etlua", ns)
	self:update(state)
	return self.refs
end

function Controller:menu(row)
	local kindId = row.kindId or row.id
	local kind = Files.kindById(kindId)
	return {{title = "Show Largest " .. (kind and kind.name or "Files"), systemImage = "doc.fill", action = function() self.showFiles(kindId) end}}
end

-- The chart and headline re-render only when the set of kinds changes; list
-- rows update in place.
function Controller:update(state)
	if not self.template then return end
	local kinds, extensions = Files.kinds(self.model)
	local all = 0
	for _, kind in ipairs(kinds) do all = all + kind.bytes end
	local marks, labels = {}, {}
	for _, kind in ipairs(kinds) do
		table.insert(marks, {id = kind.id, name = kind.name, color = kind.color, bytes = kind.bytes})
		table.insert(labels, kind.name .. " " .. kind.size)
	end
	-- The headline names the largest kind a person can act on; "Other files"
	-- and databases belong to apps.
	local headline
	for _, kind in ipairs(kinds) do
		if kind.id ~= "other" and kind.id ~= "databases" then headline = kind; break end
	end
	headline = headline or kinds[1]
	local actions = {
		kindMenu = function(_, _, row) return self:menu(row) end,
		openKind = function(_, _, row) if row then self.showFiles(row.kindId or row.id) end end,
	}
	for _, kind in ipairs(kinds) do actions["kind_" .. kind.id] = function() self.showFiles(kind.id) end end
	local _, refs = self.template:update({kinds = marks, total = Model.size(all),
		summary = #kinds == 0 and "Measuring files…" or (Model.size(all) .. " in files across " .. #kinds .. " kinds"),
		accessibilityLabel = "File types: " .. table.concat(labels, ", "),
		headline = headline and {id = headline.id, title = headline.name .. " · " .. headline.size, advice = headline.advice} or {},
		actions = actions})
	self.refs = refs
	for _, kind in ipairs(kinds) do kind.detail = Model.count(kind.count) end
	refs.kinds:replaceRows(kinds)
	for _, row in ipairs(extensions) do row.detail = Model.count(row.count) end
	refs.extensions:replaceRows(extensions)
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
