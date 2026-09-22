local Constraints = require("apps.diskmap.models.Constraints")

local Resources = {}
local rowMethods = {}
local owners = setmetatable({}, {__mode = "k"})
local states = setmetatable({}, {__mode = "k"})

local function copySequence(sequence)
	local result = {}
	for index, value in ipairs(sequence or {}) do result[index] = value end
	return result
end

local function checkDefinition(definition, context, active, prepared)
	if active[definition] then return false, {code = "cycle", message = "Resource definitions must not contain cycles."} end
	local ok, err = Constraints.evaluate("registration", {
		definition = definition, ids = context.ids, paths = context.paths, parentId = context.parentId,
	})
	if not ok then return false, err end
	active[definition] = true
	local node = {definition = definition, parent = context.parent, children = {}, parentId = context.parentId}
	prepared[#prepared + 1] = node
	context.ids[definition.id] = true
	if definition.path then context.paths[definition.path] = true end
	for _, child in ipairs(definition.children or {}) do
		local childNodeIndex = #prepared + 1
		local childOk, childErr = checkDefinition(child, {ids = context.ids, paths = context.paths, parent = node, parentId = definition.id}, active, prepared)
		if not childOk then return false, childErr end
		node.children[#node.children + 1] = prepared[childNodeIndex]
	end
	active[definition] = nil
	return true
end

local function inherited(definition, parent, key, fallback)
	return definition[key] or parent and parent[key] or fallback
end

local function bind(collection, node, parentRow)
	local state = states[collection]
	local definition, row = node.definition, {}
	for key, value in pairs(definition) do
		if key ~= "children" and key ~= "parentId" then row[key] = value end
	end
	row.icon = inherited(definition, parentRow, "icon", "doc")
	row.color = inherited(definition, parentRow, "color", "systemGray")
	row.appIcon = inherited(definition, parentRow, "appIcon", nil)
	setmetatable(row, state.rowMetatable)
	owners[row] = collection
	state.byId[row.id] = row
	if row.path then state.byPath[row.path] = row end
	state.parentByRow[row] = parentRow
	if definition.children ~= nil then state.childrenByRow[row] = {} end
	if parentRow then
		local children = state.childrenByRow[parentRow]
		children[#children + 1] = row
	else
		state.rootRows[#state.rootRows + 1] = row
	end
	if definition.children == nil then
		state.leafRows[#state.leafRows + 1] = row
	end
	for _, child in ipairs(node.children) do bind(collection, child, row) end
	return row
end

function Resources.new(model, definitions)
	if type(model) ~= "table" or type(definitions) ~= "table" then return nil, {code = "malformed_definition", message = "Resources requires a model and definition array."} end
	local collection = {model = model}
	local state = {
		byId = {}, byPath = {}, rootRows = {}, leafRows = {},
		parentByRow = setmetatable({}, {__mode = "k"}), childrenByRow = setmetatable({}, {__mode = "k"}),
	}
	state.rowMetatable = {__index = rowMethods}
	states[collection] = state
	local context = {ids = {}, paths = {}}
	local prepared = {}
	for _, definition in ipairs(definitions) do
		local ok, err = checkDefinition(definition, context, {}, prepared)
		if not ok then return nil, err end
	end
	for _, node in ipairs(prepared) do
		if not node.parent then bind(collection, node, nil) end
	end
	return setmetatable(collection, {__index = Resources})
end

function Resources:find(id)
	return states[self].byId[id]
end

function Resources:roots()
	return copySequence(states[self].rootRows)
end

function Resources:leaves()
	return copySequence(states[self].leafRows)
end

function Resources:add(parentId, definition)
	local state = states[self]
	local parent = state.byId[parentId]
	if not parent then return nil, {code = "invalid_parent", message = "Resource parent is not registered: " .. tostring(parentId)} end
	if parent:isLeaf() then return nil, {code = "parent_not_group", message = "Resources can only be added to a group."} end
	local context = {ids = {}, paths = {}, parent = parent, parentId = parentId}
	for id in pairs(state.byId) do context.ids[id] = true end
	for path in pairs(state.byPath) do context.paths[path] = true end
	local prepared = {}
	local ok, err = checkDefinition(definition, context, {}, prepared)
	if not ok then return nil, err end
	local first
	local function commit(node, ancestor)
		local row = bind(self, node, ancestor)
		first = first or row
		for _, child in ipairs(node.children) do commit(child, row) end
	end
	commit(prepared[1], parent)
	return first
end

function rowMethods:getParent()
	local collection = owners[self]
	local state = collection and states[collection]
	return state and state.parentByRow[self] or nil
end

function rowMethods:getChildren()
	local collection = owners[self]
	local state = collection and states[collection]
	return state and copySequence(state.childrenByRow[self]) or {}
end

function rowMethods:isLeaf()
	local collection = owners[self]
	local state = collection and states[collection]
	return not state or state.childrenByRow[self] == nil
end

function rowMethods:getMeasurement()
	local collection = owners[self]
	return collection and collection.model.measurements[self.id] or nil
end

function rowMethods:isKept()
	local row = self
	while row do
		local collection = owners[row]
		if collection and collection.model.kept[row.id] then return true end
		row = row:getParent()
	end
	return false
end

function rowMethods:validateTrash()
	local collection = owners[self]
	if not collection then return false, {code = "unknown_resource", message = "Resource is not registered."} end
	return Constraints.evaluate("trash", {row = self, action = "trash"})
end

return Resources
