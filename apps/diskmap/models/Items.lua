local Model = require("data.model")

-- Everything Diskmap measured, one row per thing a person can act on: a
-- cache folder, a DerivedData project, a simulator device, a worktree, a
-- build folder, a System Data contributor. Sources (services/Sources.lua)
-- replace a category's rows when they finish; pages read them.
--
--   id        the path, or "<kind>:<identifier>" for things without one
--   category  knowledge/Categories id;  section  the list on its page
--   path, name, owner, what
--   bytes     measured size, nil until measured;  used  when something inside was last written
--   state     measured | missing | denied | failed | pending
--   verdict   safe | review | owner | system | keep   (helpers/Verdict.lua)
--   reason    the sentence that justifies the verdict, from a fact Diskmap computed
--   action    trash | erase | delete | runtimeDelete | worktreeRemove | worktreePrune | none
--   admin     owned by root: Finder asks for an administrator
--   marker    the project file that proves a build folder is one
--   bundleId  the app whose running blocks the removal
--   parent    the expanded location this row is a child of
local Items = Model:extend("items", {constraints = {
	id = function(_, id) if type(id) ~= "string" or id == "" then return "An item needs an id." end end,
	category = function(_, category) if type(category) ~= "string" then return "An item needs a category." end end,
}})

-- Replaces the rows of `category` with `rows`; a Keep choice survives.
function Items:replace(category, rows)
	for _, row in ipairs(self:select({category = category})) do row:delete() end
	for _, row in ipairs(rows) do
		row.category = category
		assert(self:create(row))
	end
end

function Items:inCategory(category)
	return self:select({category = category}, {order = function(a, b)
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.id < b.id
	end})
end

-- The rows of one section of a category, largest first.
function Items:inSection(category, section)
	local rows = {}
	for _, row in ipairs(self:inCategory(category)) do
		if row.section == section then table.insert(rows, row) end
	end
	return rows
end

function Items:byPath(path)
	return self:find({path = path})
end

-- Total measured bytes of a category, and the bytes its safe rows hold.
function Items:totals(category)
	local bytes, safe, pending = 0, 0, 0
	for _, row in ipairs(self:select({category = category})) do
		if row.state == "pending" then pending = pending + 1 end
		bytes = bytes + (row.bytes or 0)
		if row.verdict == "safe" then safe = safe + (row.bytes or 0) end
	end
	return bytes, safe, pending
end

-- Something left the disk: its row goes, and the folder it was listed
-- under shrinks by as much. Nothing is measured again.
function Items:removed(path, bytes)
	local row = self:byPath(path)
	if not row then return false end
	local parent = row.parent and self:find(row.parent)
	if parent and parent.bytes then parent.bytes = math.max(0, parent.bytes - (bytes or row.bytes or 0)) end
	row:delete()
	return true
end

-- A row shrank (a simulator erased) but is still there.
function Items:resized(path, bytes)
	local row = self:byPath(path)
	if not row then return false end
	row.bytes = bytes
	return true
end

return Items
