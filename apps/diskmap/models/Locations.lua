local Model = require("data.model")
local Constraints = require("apps.diskmap.helpers.Constraints")
local Format = require("apps.diskmap.helpers.Format")
local Status = require("apps.diskmap.helpers.Status")
local Snapshot = require("apps.diskmap.helpers.Snapshot")
local SystemDetails = require("apps.diskmap.helpers.SystemDetails")

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

-- The words a location may use to say what it is and who removes it
-- (catalog/Definitions.lua explains each).
Locations.natures = {cache = true, build = true, download = true, library = true, log = true, leftover = true, appData = true, personal = true, system = true}
Locations.removers = {trash = true, ownerCommand = true, owner = true, setting = true, restart = true, update = true, finder = true, none = true}
local ACTIONS = {trash = "trash", ownerCommand = "ownerCleanup", setting = "settings"}

-- Fills a leaf's `policy` (the label lists show) and `action` (what its
-- button does) from its nature and remover, when the entry names neither:
-- Diskmap may only trash or command what says so, a system location is
-- system managed, and everything else is reviewed where its advice says.
function Locations.classify(row)
	row.nature = row.nature or "appData"
	row.remover = row.remover or "finder"
	assert(Locations.natures[row.nature], "Unknown nature for " .. tostring(row.id) .. ": " .. tostring(row.nature))
	assert(Locations.removers[row.remover], "Unknown remover for " .. tostring(row.id) .. ": " .. tostring(row.remover))
	row.policy = row.policy or ((row.remover == "trash" or row.remover == "ownerCommand") and "Rebuildable"
		or row.nature == "system" and "System managed" or "Review")
	row.action = row.action or ACTIONS[row.remover] or "finder"
	return row
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
	if definition.children == nil then Locations.classify(row) end
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

-- The catalog advice of location `id`, or nil (the Storage Guide reads it).
function Locations.advice(id)
	local row = Locations:find(id)
	return row and row.advice
end

function Locations:findPath(path)
	for _, row in ipairs(self:leaves()) do if row.path == path then return row end end
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

-- Whether Keep protects `id`: a location (itself or through a kept group),
-- or anything else a page keeps under a key of its own (a simulator device,
-- a worktree). A plain function, for the helpers that take a lookup.
function Locations.keeps(id)
	local location = Locations:find(id)
	if location then return location:isKept() end
	return Model.db.kept[id] == true
end



-- The macOS installer apps among the locations, each {id, name, path, bytes}.
function Locations:installers()
	local rows = {}
	for _, row in ipairs(self:leaves()) do
		if row.path and row.name:match("^Install macOS .+%.app$") then
			local m = row:measurement()
			table.insert(rows, {id = row.id, name = row.name, path = row.path, bytes = m and m.bytes})
		end
	end
	return rows
end

function Location:validateTrash()
	return Constraints.evaluate("trash", {row = self, action = "trash"})
end

function Location:validateEmpty()
	return Constraints.evaluate("empty", {row = self, action = "empty"})
end

-- Scan roots partition storage: a parent's measurement excludes separately
-- catalogued descendants. Rejoin those disjoint amounts for folder inspection.
function Locations:folderBytes(path)
	local bytes, measured = 0, false
	for _, row in ipairs(self:leaves()) do
		if row.path and (row.path == path or row.path:sub(1, #path + 1) == path .. "/") then
			local measurement = row:measurement()
			if measurement and measurement.bytes ~= nil then
				bytes, measured = bytes + measurement.bytes, true
			end
		end
	end
	return measured and bytes or nil
end

-- A location opens its contents; catalog exceptions use dedicated pages.
-- Groups without a filesystem path drill into the semantic Storage Map.
function Location:destination()
	if self.page == "sdks" then return {page = "sdks", params = {id = self.id}} end
	local row = self
	while row do
		if row.page then return {page = row.page} end
		row = row:parent()
	end
	if self.path then return {page = "folder", params = {path = self.path}} end
	return {page = "map", params = {focus = self.id}}
end

local function ancestry(row)
	local names, parent = {}, row:parent()
	while parent do table.insert(names, 1, parent.name); parent = parent:parent() end
	return table.concat(names, " › ")
end

-- The largest individually measured resources across every category: the
-- quickest answer to "what is eating my storage?". A row opens by its own id,
-- wherever its location sends it.
function Locations:largest(disk, limit)
	local model = Model.db
	local rows = {}
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id]
		if m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0 then
			local root = row
			while root:parent() do root = root:parent() end
			table.insert(rows, {id = row.id, rootId = root.id,
				name = row.name, subtitle = ancestry(row),
				bytes = m.bytes,
				share = used and m.bytes / used or 0, shareText = Format.percent(m.bytes, used),
				icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
				impact = row.policy == "Essential" and "Keep" or row.policy == "Rebuildable" and "Rebuildable"
					or row.policy == "System managed" and "System managed" or "Review",
				kept = row:isKept()})
			rows[#rows].detail = rows[#rows].kept and "Kept" or rows[#rows].impact
			Format.sizeLabel(rows[#rows], m.status, m.bytes)
			Status.apply(rows[#rows])
		end
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	if limit then while #rows > limit do table.remove(rows) end end
	-- Bars compare items with the largest one, like a ranked bar chart; the
	-- label keeps the share of used capacity.
	for _, row in ipairs(rows) do row.relative = row.bytes / rows[1].bytes end
	return rows
end

local function leaves(row, result)
	if row:isLeaf() then table.insert(result, row); return end
	for _, child in ipairs(row:children()) do leaves(child, result) end
end
-- Ledger-only breakdown of the System Data group: ranked measured
-- contributors, the group total and virtual-memory allocation when measured.
-- Anything macOS does not expose as files (snapshot exclusive allocation,
-- purgeable space, metadata) cannot appear here by construction.
function Locations:systemData()
	local model = Model.db
	local group = Locations:find("system-data")
	local found = {}
	if group then leaves(group, found) end
	local contributors, totalBytes = {}, 0
	for _, row in ipairs(found) do
		local m = model.measurements[row.id]
		if m and m.status == "complete" and (m.bytes or 0) > 0 then
			totalBytes = totalBytes + m.bytes
			table.insert(contributors, {id = row.id, name = row.name, bytes = m.bytes, size = Format.size(m.bytes)})
		end
	end
	table.sort(contributors, function(a, b) return a.bytes > b.bytes end)
	local measuredLocations = #contributors
	while #contributors > 5 do contributors[#contributors] = nil end
	local vm = model.measurements.vm
	return {
		contributors = contributors,
		measuredLocations = measuredLocations,
		knownLocations = #found,
		total = totalBytes > 0 and {bytes = totalBytes, size = Format.size(totalBytes)} or nil,
		vm = vm and vm.status == "complete" and (vm.bytes or 0) > 0 and {bytes = vm.bytes, size = Format.size(vm.bytes)} or nil,
	}
end

-- Metadata only: recognize versioned SQLite sidecars without opening credentials or history.
function Locations:addAgentFiles(entries)
	local paths = {}; for _, row in ipairs(Locations:leaves()) do if row.path then paths[row.path] = true end end
	for _, entry in ipairs(entries or {}) do
		local parent = Locations:find(entry.agent)
		if parent and not parent:isLeaf() and entry.path and not paths[entry.path] then
			local name = entry.name or ""
			local directories = {node_repl = "Tool runtime", attachments = "Generated assets", browser = "Browser data", ["computer-use"] = "Generated assets", tmp = "Temporary data", [".tmp"] = "Temporary data", vendor_imports = "Plugins", memories = "Sessions & memory", ["dictation-history"] = "Sessions & history", ["file-history"] = "Checkpoints & history", rules = "Settings", automations = "Settings"}
			local kind = name:match("%.sqlite") or name:match("%.db")
			kind = kind and "Database" or name:match("%.jsonl$") and "History" or (name:match("%.toml$") or name:match("%.json$")) and "Settings" or name:match("%.log$") and "Logs" or name:match("%.txt$") and "Logs"
			kind = kind or directories[name] or "Unclassified"
			if kind then
				local row = {id = entry.agent .. "-file-" .. name, name = kind .. " · " .. name, subtitle = "Persistent tool state; review only", path = entry.path,
					policy = "Review", action = "finder", agent = entry.agent, icon = parent.icon, color = parent.color}
				local added, err = Locations:add(parent.id, row)
				if not added then return false, err end
				paths[added.path] = true
			end
		end
	end
	return true
end

-- Measured bytes per catalog location. Denied, excluded and unmeasured
-- locations are left out, so they never read as growth or shrinkage.
function Locations:totals()
	local model = Model.db
	local totals = {}
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id]
		if m and (m.status == "complete" or m.status == "partial") and m.bytes then totals[row.id] = m.bytes end
	end
	return totals
end


local function since(createdAt)
	return (os.date("%b %e", createdAt):gsub("  ", " "))
end

-- Locations that grew or shrank since the snapshot, largest change first,
-- with totals for the section summary. Locations measured on only one side
-- are skipped: a new tool or a newly denied folder is not a change in size.
function Locations:changesSince(baseline)
	if not baseline or not baseline.totals then return nil end
	local now = Locations:totals()
	local rows, grew, freed = {}, 0, 0
	for id, after in pairs(now) do
		local before = baseline.totals[id]
		local resource = Locations:find(id)
		if before and resource and math.abs(after - before) >= Snapshot.minimumChange then
			local delta = after - before
			if delta > 0 then grew = grew + delta else freed = freed - delta end
			table.insert(rows, {id = id, name = resource.name, subtitle = ancestry(resource), icon = resource.icon, color = resource.color,
				appIcon = resource.appIcon, path = resource.path, delta = delta, bytes = after, size = Format.size(after),
				before = Format.size(before), grew = delta > 0,
				text = (delta > 0 and "+" or "−") .. Format.size(math.abs(delta))})
		end
	end
	table.sort(rows, function(a, b)
		if math.abs(a.delta) ~= math.abs(b.delta) then return math.abs(a.delta) > math.abs(b.delta) end
		return a.id < b.id
	end)
	local largest = rows[1] and math.abs(rows[1].delta) or 0
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and math.abs(row.delta) / largest or 0
		row.detail, row.shareText = row.text, ""
		row.levelColor = row.grew and "systemOrange" or "systemGreen"
	end
	local date = baseline.createdAt and since(baseline.createdAt) or "the snapshot"
	local parts = {}
	if grew > 0 then table.insert(parts, Format.size(grew) .. " more") end
	if freed > 0 then table.insert(parts, Format.size(freed) .. " freed") end
	return {rows = rows, since = date, grew = grew, freed = freed,
		title = "Changes Since " .. date,
		detail = #rows == 0 and ("No location changed by more than " .. Format.size(Snapshot.minimumChange) .. " since the " .. date .. " snapshot.")
			or (Format.plural(#rows, "location") .. " changed since the " .. date .. " snapshot · " .. table.concat(parts, ", "))}
end


-- Logical sizes this much larger than the allocation are worth mentioning.
Locations.logicalThreshold = 100e6
function Locations:details(id)
	local model = Model.db
	-- Suggestions are computed from locations, so they load when first asked.
	local Suggestions = require("apps.diskmap.models.Suggestions")
	local row = Locations:find(id); if not row then return nil end
	local m = model.measurements[id]
	local ownerCleanupReady = row.action ~= "ownerCleanup" or (m and m.status == "complete" and (m.bytes or 0) > 0)
	local text = row.advice or row.subtitle .. ". " .. (row:isLeaf() and "Review this data in its owning app. Size alone does not establish that it is disposable." or "Review its measured resources by impact below.")
	for _, candidate in ipairs(Suggestions:ranked()) do
		if candidate.id == id then text = candidate.evidence .. "\n\n" .. candidate.subtitle .. "\n\n" .. text; break end
	end
	if id == "system-data" then text = text .. "\n\n" .. SystemDetails.format(Locations:systemData()) end
	local measurement = ""
	if m then
		if m.status == "partial" then measurement = "\nAt least " .. Format.size(m.bytes) .. " measured · partial"
		elseif m.status == "complete" then measurement = "\n" .. Format.size(m.bytes) .. " measured"
		elseif m.status == "denied" then measurement = "\nNot measured · access restricted"
		elseif m.status == "protected" then measurement = "\nNot measured · macOS keeps every app out of this location"
		elseif m.status == "calculating" then measurement = "\nCalculating…"
		elseif m.status == "excluded" then measurement = "\nNot scanned"
		else measurement = "\n" .. m.status end
		-- Sparse files and disk images are smaller on disk than they say.
		if m.logicalBytes and m.bytes and m.logicalBytes - m.bytes >= Locations.logicalThreshold then
			measurement = measurement .. " · " .. Format.size(m.logicalBytes) .. " logical size (sparse files use less on disk)"
		end
		if m.cloudFiles and m.cloudFiles > 0 then
			measurement = measurement .. "\n" .. Format.count(m.cloudFiles) .. (m.cloudFiles == 1 and " file" or " files")
				.. " in iCloud only (" .. Format.size(m.cloudBytes or 0) .. "); they use no space on this Mac and are never downloaded to measure them"
		end
	end
	return {name = row.name, text = text, location = (row.path or "Multiple known locations") .. measurement,
		manageTitle = row.action == "simulators" and "Show Simulators" or row.action == "sdks" and "Show SDKs" or row.action == "trash" and "Review Move to Trash…" or row.action == "empty" and "Empty Trash…" or row.action == "ownerCleanup" and "Clear Cache…" or row.action == "settings" and (({siri = "Open Siri Settings", dictation = "Open Dictation Settings", voices = "Open Accessibility Settings", wallpaper = "Open Wallpaper Settings"})[row.settingsSection] or "Open System Settings") or row.action == "xcode" and "Open Xcode" or row.action == "docker" and "Open Docker" or nil,
		canManage = row:isLeaf() and ownerCleanupReady and (row.action ~= "trash" or row:validateTrash()) and (row.action ~= "empty" or row:validateEmpty()) and (row.path ~= nil or row.action == "settings"),
		keepTitle = model.kept[id] and "Stop Keeping" or "Keep"}
end

return Locations
