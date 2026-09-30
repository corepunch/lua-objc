local ns = require("AppKit")
local Template = require("ui.template")
local Controller = {}; Controller.__index = Controller

-- One controller for every page that lists catalog resources: Largest Items,
-- Clean Up, and each kind of work in knowledge/Workflows.lua (Developer,
-- Music Production, …). What a page shows is its `page` table, built by a
-- model:
--
--   view       the template in views/
--   children   {ref = template}: retained child templates mounted in a ref
--   present(model, state) → {
--     template   data the template renders from (its structure)
--     lists      {ref = rows}: rows for each list
--     texts      {ref = text}
--     hidden     {ref = boolean}
--     children   {ref = data} for each child template
--     links      {action = {open = id} | {page = id, filter = n} | {settings = section}}
--   }
--
-- Behaviour is the same on every page: a row's menu is its resource's menu,
-- and opening a row goes where Destinations sends that resource. A row that
-- stands for another page (`row.page`) opens that page. `handlers.open(id)`
-- opens a resource, `handlers.show(page, filter)` a sidebar page and
-- `handlers.settings(section)` System Settings; `actions` builds row menus.
function Controller.new(model, actions, handlers, page)
	return setmetatable({model = model, actions = actions, handlers = handlers, page = page}, Controller)
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/" .. self.page.view .. ".etlua", ns)
	self.children = {}
	self:update(state)
	return self.refs
end

function Controller:menu(row)
	if row.page then
		return {{title = "Open " .. (row.pageName or "Page"), systemImage = "arrow.right.circle",
			action = function() self.handlers.show(row.page, row.filter) end}}
	end
	return self.actions:resource(row.id)
end

function Controller:activate(row)
	if not row then return end
	if row.page then self.handlers.show(row.page, row.filter) else self.handlers.open(row.id) end
end

function Controller:follow(link)
	if link.open then self.handlers.open(link.open)
	elseif link.page then self.handlers.show(link.page, link.filter)
	elseif link.settings then self.handlers.settings(link.settings) end
end

-- The template carries only structure, so scan progress updates rows and
-- labels in place instead of rebuilding the page under the reader.
function Controller:update(state)
	if not self.template then return end
	local presented = self.page.present(self.model, state or {})
	local actions = {
		rowMenu = function(_, _, row) return self:menu(row) end,
		open = function(_, _, row) self:activate(row) end,
	}
	for name, link in pairs(presented.links or {}) do actions[name] = function() self:follow(link) end end
	local data = presented.template or {}
	data.actions = actions
	local _, refs = self.template:update(data)
	self.refs = refs
	for id, rows in pairs(presented.lists or {}) do refs[id]:replaceRows(rows) end
	for id, text in pairs(presented.texts or {}) do refs[id].text = text end
	for id, hidden in pairs(presented.hidden or {}) do refs[id].hidden = hidden end
	for id, view in pairs(self.page.children or {}) do
		self.children[id] = self.children[id] or self.template:child(id, "apps/diskmap/views/" .. view .. ".etlua")
		local childData = presented.children and presented.children[id] or {}
		childData.actions = actions
		self.children[id]:update(childData)
	end
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs, self.children = nil, nil, nil
end

return Controller
