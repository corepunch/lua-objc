local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local Paths = require("apps.diskmap.helpers.Paths")

-- Items marked for cleanup across every page, in the order they were marked:
-- the store's `marks` table, one row per item {path, name, bytes, source,
-- consequence, resourceId}. Marking never changes the disk; the review page
-- moves items to the Trash one at a time, after checking each again.
local Marks
Marks = Model:extend("marks", {primaryKey = "path", relations = {
	-- `mark:location()`: the catalog location a mark stands for, if it is one.
	{"location", belongsTo = "locations", key = "resourceId"},
}, constraints = {
	-- Flags may refer to protected locations; only path identity is validated.
	path = function(_, path)
		local ok, reason = Paths.validateReview(path)
		if not ok then return reason end
	end,
}})
local within = Paths.within

-- Adds an item {path, name, bytes, consequence, source}. Returns ok and a
-- refusal reason.
function Marks:add(item)
	if type(item) ~= "table" then return false, "Nothing selected." end
	local refusal = Marks.constraints.path(item, item.path)
	if refusal then return false, refusal end
	local key = Paths.normalize(item.path)
	for _, mark in ipairs(self:all()) do
		-- A parent and its child would be counted and moved twice.
		local parent = Paths.normalize(mark.path)
		if key ~= parent and within(key, parent) then return false, "Included through marked folder: " .. mark.path end
		if key == parent then
			item.path = mark.path
			for field in pairs(mark) do mark[field] = nil end
			mark:update(item)
			return true
		end
	end
	self:create(item)
	for _, mark in ipairs(self:all()) do
		local child = Paths.normalize(mark.path)
		if child ~= key and within(child, key) then mark:delete() end
	end
	return true
end

-- Removes the item marked exactly at `path`.
function Marks:remove(path)
	local mark, exact = self:covering(path)
	if not exact then return false end
	return mark:delete()
end

function Marks:contains(path)
	local _, exact = self:covering(path)
	return exact == true
end

-- The mark at or above `path`, and whether it is exactly there. Exact marks
-- and inclusion through a folder are different decisions: unmarking a file
-- must never remove its enclosing folder's mark.
function Marks:covering(path)
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return nil end
	local key = Paths.normalize(path)
	for _, mark in ipairs(self:all()) do
		local parent = Paths.normalize(mark.path)
		if within(key, parent) then return mark, key == parent end
	end
end

function Marks:clear() Model.db.marks = {} end

-- The review page's rows and their total.
function Marks:rows()
	local rows, bytes = {}, 0
	for _, item in ipairs(self:all()) do
		local path = item.path
		bytes = bytes + (item.bytes or 0)
		table.insert(rows, {id = path, path = path, name = item.name or path:match("([^/]+)$"),
			subtitle = item.source and (item.source .. " · " .. path) or path, bytes = item.bytes,
			size = Format.size(item.bytes), reviewOnly = item.reviewOnly, consequence = item.reviewOnly and "Flagged for inspection. Manage this item through its owning app or System Settings." or item.consequence or "Moves to the Trash only after confirmation."})
	end
	return rows, bytes
end

function Marks:summary()
	local rows, bytes = self:rows()
	if #rows == 0 then return "Nothing flagged for review" end
	return #rows .. (#rows == 1 and " item · " or " items · ") .. Format.size(bytes)
end

return Marks
