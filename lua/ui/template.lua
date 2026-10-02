-- Retained etlua component boundary. The first update mounts the template;
-- later updates reconcile the new description with the mounted views (see
-- xml.reconcile): unchanged nodes keep their native views, changed
-- attributes apply in place, and only nodes whose structure changed are
-- rebuilt. Updates apply at once; nothing animates.
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
	-- Actions must be current before reconciliation: new controls bind
	-- through the dispatch table, and a failure keeps the previous actions.
	local previousActions = self.actions
	self.actions = data.actions or {}
	local ok, err
	if self.mounted then
		ok, err = pcall(self.ns.Scope.withScope, self.scope, xml.reconcile, self.mounted, description, self.ns, self.host)
	else
		local scope = self.ns.Scope.new()
		ok, err = pcall(self.ns.Scope.withScope, scope, xml.mount, description, self.ns, self.host)
		if ok then self.scope, self.mounted = scope, err else scope:dispose() end
	end
	if not ok then self.actions = previousActions; error(err, 0) end
	self.view, self.refs = self.mounted.view, self.mounted.refs
	self.description, self.bindings = description, bindings
	return self.view, self.refs
end
-- Mount a retained template into one of this template's refs. The child
-- lives in the scope of the node that owns the ref, so rebuilding that node
-- disposes the child too.
function Template:child(ref, path)
	assert(self.refs and self.refs[ref], "Template child requires a mounted ref: " .. tostring(ref))
	local scope = xml.scopeOf(self.mounted, ref) or self.scope
	return self.ns.Scope.withScope(scope, Template.new, self.refs[ref], path, self.ns)
end
function Template:isDisposed() return self.closed == true end
function Template:dispose()
	if self.closed then return end
	self.closed = true
	if self.mounted then xml.unmount(self.mounted, self.ns) end
	if self.scope then self.scope:dispose() end
	self.view, self.refs, self.mounted, self.description, self.bindings, self.actions = nil, nil, nil, nil, nil, {}
end
return Template
