local ns = require("AppKit")
local Template = require("ui.template")
local Developer = require("apps.diskmap.models.Developer")
local Controller = {}; Controller.__index = Controller

-- `handlers.open(id)` opens a category sheet, `handlers.simulators()` the
-- Simulators page and `handlers.sdks(row)` the SDK sheet; `actions` builds
-- row menus.
function Controller.new(model, actions, handlers)
	return setmetatable({model = model, actions = actions, handlers = handlers}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Developer.etlua", ns)
	self:update(state)
	return self.refs
end

-- Opening a row goes where its data is managed: grouped rows open their own
-- list, simulator devices their page, SDKs their sheet, anything else the
-- category that owns it.
function Controller:activate(row)
	local resource = row and self.model.resources:find(row.id)
	if not resource then return end
	if resource.action == "simulators" then self.handlers.simulators()
	elseif resource.action == "sdks" then self.handlers.sdks(resource)
	elseif not resource:isLeaf() then self.handlers.open(resource.id)
	else
		local parent = resource:getParent()
		self.handlers.open(parent and parent.id or resource.id)
	end
end

-- The template carries only the section structure, so scan progress updates
-- rows and labels in place instead of rebuilding the page under the reader.
function Controller:update(state)
	if not self.template then return end
	local data = Developer.presentation(self.model, state and state.query)
	local structure = {}
	for _, section in ipairs(data.sections) do
		table.insert(structure, {id = section.id, title = section.title, detail = section.detail})
	end
	local _, refs = self.template:update({sections = structure, calculating = data.calculating and #structure == 0, actions = {
		rowMenu = function(_, _, row) return self.actions:resource(row.id) end,
		open = function(_, _, row) self:activate(row) end,
		simulators = function() self.handlers.simulators() end,
	}})
	self.refs = refs
	for _, section in ipairs(data.sections) do
		refs["list_" .. section.id]:replaceRows(section.rows)
		refs["size_" .. section.id].text = section.size
	end
	refs.developerTotal.text = data.calculating and "Measuring developer storage…"
		or (data.total .. " across Xcode, packages, containers and AI tools"
			.. (data.rebuildable > 0 and (" · " .. data.rebuildableSize .. " rebuildable now") or ""))
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
