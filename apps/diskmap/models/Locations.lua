local Model = require("data.model")
local Constraints = require("apps.diskmap.helpers.Constraints")

-- The catalog's locations: the tree of categories (groups) and the places on
-- disk they measure (leaves), built from catalog definitions and the ones a
-- scan discovers. Rows are Lapis-style rows of the store's `locations`
-- table; the store keeps one index beside them, so a location is found by
-- id or path, and its parent and children are known, without a scan of the
-- table.
--
--   Locations:find("xcode"):parent().name
--   Locations:owner(path)                  the deepest location at or above a path
--   Locations:add("developer", definition) a location a scan discovered
--   location:children(), :isLeaf(), :measurement(), :isKept(), :destination()
local Locations, Location = Model:extend("locations")

local function index(db)
	return db and db.locationIndex
end

local function copy(sequence)
	local result = {}
	for position, value in ipairs(sequence or {}) do result[position] = value end
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
	table.insert(prepared, node)
	context.ids[definition.id] = true
	if definition.path then context.paths[definition.path] = true end
	for _, child in ipairs(definition.children or {}) do
		local childNodeIndex = #prepared + 1
		local childOk, childErr = checkDefinition(child, {ids = context.ids, paths = context.paths, parent = node, parentId = definition.id}, active, prepared)
		if not childOk then return false, childErr end
		table.insert(node.children, prepared[childNodeIndex])
	end
	active[definition] = nil
	return true
end

local function inherited(definition, parent, key, fallback)
	return definition[key] or parent and parent[key] or fallback
end

-- Stores the row of `node` and its descendants under `parentRow`.
local function store(db, node, parentRow)
	local state = db.locationIndex
	local definition, row = node.definition, {}
	for key, value in pairs(definition) do
		if key ~= "children" and key ~= "parentId" then row[key] = value end
	end
	row.icon = inherited(definition, parentRow, "icon", "doc")
	row.color = inherited(definition, parentRow, "color", "systemGray")
	row.appIcon = inherited(definition, parentRow, "appIcon", nil)
	Locations:load(row)
	table.insert(db.locations, row)
	state.byId[row.id] = row
	if row.path then state.byPath[row.path] = row end
	state.parents[row] = parentRow
	if definition.children ~= nil then state.children[row] = {} end
	if parentRow then table.insert(state.children[parentRow], row) else table.insert(state.roots, row) end
	if definition.children == nil then table.insert(state.leaves, row) end
	for _, child in ipairs(node.children) do store(db, child, row) end
	return row
end

-- Fills `db.locations` from catalog definitions; nil and an error when a
-- definition breaks a constraint.
function Locations.seed(db, definitions)
	if type(db) ~= "table" or type(definitions) ~= "table" then
		return nil, {code = "malformed_definition", message = "Locations need a store and a definition array."}
	end
	db.locations = {}
	db.locationIndex = {byId = {}, byPath = {}, roots = {}, leaves = {}, parents = {}, children = {}, added = {}}
	local context, prepared = {ids = {}, paths = {}}, {}
	for _, definition in ipairs(definitions) do
		local ok, err = checkDefinition(definition, context, {}, prepared)
		if not ok then return nil, err end
	end
	for _, node in ipairs(prepared) do
		if not node.parent then store(db, node, nil) end
	end
	return db.locations
end

function Locations:find(id)
	local state = index(Model.db)
	return state and id ~= nil and state.byId[id] or nil
end

function Locations:roots()
	local state = index(Model.db)
	return copy(state and state.roots)
end

function Locations:leaves()
	local state = index(Model.db)
	return copy(state and state.leaves)
end

-- The measured location that owns an absolute path: the deepest catalog
-- location at or above it. Scans exclude nested locations from their
-- parents, so this is also the location whose total includes the path.
function Locations:owner(path)
	local state = index(Model.db)
	local current = state and path
	while current and current ~= "" do
		local row = state.byPath[current]
		if row then return row end
		if current == "/" then break end
		local slash = current:match("^.*()/")
		current = slash == 1 and "/" or slash and current:sub(1, slash - 1) or nil
	end
	return nil
end

-- A location a scan discovered (an app, a project's build folder, a tool's
-- file), stored under the group `parentId`.
function Locations:add(parentId, definition)
	local db = Model.db
	local state = index(db)
	local parent = state and state.byId[parentId]
	if not parent then return nil, {code = "invalid_parent", message = "Resource parent is not registered: " .. tostring(parentId)} end
	if parent:isLeaf() then return nil, {code = "parent_not_group", message = "Resources can only be added to a group."} end
	local context = {ids = {}, paths = {}, parent = parent, parentId = parentId}
	for id in pairs(state.byId) do context.ids[id] = true end
	for path in pairs(state.byPath) do context.paths[path] = true end
	local prepared = {}
	local ok, err = checkDefinition(definition, context, {}, prepared)
	if not ok then return nil, err end
	local first = store(db, prepared[1], parent)
	table.insert(state.added, {parentId = parentId, definition = definition})
	return first
end

-- Locations added after the catalog loaded, in order, so another store can
-- register the same locations.
function Locations:added()
	local state = index(Model.db)
	return copy(state and state.added)
end

-- Where opening the location `id` goes (see Location:destination), or nil
-- for an id no location has.
function Locations:destination(id)
	local location = self:find(id)
	return location and location:destination()
end

-- Whether opening the location `id` leaves its category's list.
function Locations:opensElsewhere(id)
	local location = self:find(id)
	return location ~= nil and location:opensElsewhere()
end

function Location:parent()
	local state = index(Model.db)
	return state and state.parents[self] or nil
end

function Location:children()
	local state = index(Model.db)
	return copy(state and state.children[self])
end

function Location:isLeaf()
	local state = index(Model.db)
	return not state or state.children[self] == nil
end

function Location:measurement()
	return Model.db.measurements[self.id]
end

-- Kept itself or below a kept group.
function Location:isKept()
	local row, kept = self, Model.db.kept
	while row do
		if kept[row.id] then return true end
		row = row:parent()
	end
	return false
end

function Location:validateTrash()
	return Constraints.evaluate("trash", {row = self, action = "trash"})
end

function Location:validateEmpty()
	return Constraints.evaluate("empty", {row = self, action = "empty"})
end

-- Where opening the location goes. Every list, menu and link in Diskmap
-- opens a location by its own id and asks here; no page decides for itself.
-- The catalog declares the exceptions on the location: `page` names the
-- sidebar page that presents it and everything under it (Developer projects
-- on Projects, Simulator devices on Simulators, DerivedData on Xcode, every
-- app on Applications), `sheet` its own sheet (the SDKs of an Xcode
-- installation). Everything else opens in its category's list: a group as
-- itself, a location in its group with its row selected. Returns
-- {page = pageId} | {sheet = name, id = id} | {category = groupId, select = leafId or nil}.
function Location:destination()
	if self.sheet then return {sheet = self.sheet, id = self.id} end
	local row = self
	while row do
		if row.page then return {page = row.page, id = self.id} end
		row = row:parent()
	end
	if not self:isLeaf() then return {category = self.id} end
	local parent = self:parent()
	return {category = parent and parent.id or self.id, select = self.id}
end

-- Whether opening the location leaves its category's list for a page or
-- sheet of its own; such rows show the "open" button in a category list.
function Location:opensElsewhere()
	return self:destination().category == nil
end

return Locations
