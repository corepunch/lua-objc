-- Retained etlua component boundary. Unchanged descriptions preserve native
-- identity; structural/binding changes replace a scoped subtree atomically.
local xml = require("ui.xml")
local Template = {}; Template.__index = Template
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for k, v in pairs(value) do result[k] = copy(v) end
	return result
end
local function equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
function Template.new(host, path, ns)
	local self = setmetatable({host = host, path = path, ns = ns, actions = {}}, Template)
	self.dispatch = setmetatable({}, {__index = function(_, name)
		return function(...)
			local action = self.actions[name]
			if action and not self.closed then return action(...) end
		end
	end})
	local owner = ns.Scope.current(); if owner then owner:add(self) end
	return self
end
function Template:update(data)
	assert(not self.closed, "Cannot update a disposed template")
	data = data or {}
	local bindings = {}; for k, v in pairs(data) do if k ~= "actions" then bindings[k] = copy(v) end end
	local description = xml.describeFile(self.path, data)
	if self.description and self.description.source == description.source and equal(self.bindings, bindings) then
		self.actions = data.actions or {}
		return self.view, self.refs
	end
	description.data.actions = self.dispatch
	local scope = self.ns.Scope.new()
	local ok, view, refs = pcall(self.ns.Scope.withScope, scope, xml.renderDescription, description, self.ns)
	if not ok then scope:dispose(); error(view) end
	if type(view) == "table" then scope:dispose(); error("Template mounts require a view root, not a Window") end
	local previous = self.scope
	self.host:clearContainer(); self.host:add(view)
	self.scope, self.view, self.refs = scope, view, refs
	self.description, self.bindings, self.actions = description, bindings, data.actions or {}
	if previous then previous:dispose() end
	self.host:layout()
	return view, refs
end
function Template:isDisposed() return self.closed == true end
function Template:dispose()
	if self.closed then return end
	self.closed = true
	if self.scope then self.scope:dispose() end
	self.host:clearContainer()
	self.view, self.refs, self.description, self.bindings, self.actions = nil, nil, nil, nil, {}
end
return Template
