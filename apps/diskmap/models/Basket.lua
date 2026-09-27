local Model = require("apps.diskmap.Model")
local Basket = {}; Basket.__index = Basket

-- Items marked for cleanup across every page. Marking never changes the
-- disk; the review sheet moves items to the Trash one at a time, after
-- checking each again.

-- Locations that are never cleanup targets themselves, however they were
-- marked: the disk, system folders, the home folder and its standard folders,
-- and mount points. Items inside them are allowed.
local REFUSED = {"/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/private", "/usr", "/bin",
	"/sbin", "/opt", "/etc", "/var", "/cores", "/nix", "/Network"}
local HOME_FOLDERS = {"", "/Library", "/Desktop", "/Documents", "/Downloads", "/Developer", "/Movies", "/Music",
	"/Pictures", "/Public", "/Applications", "/.Trash", "/Library/Caches", "/Library/Application Support",
	"/Library/Containers", "/Library/Group Containers", "/Library/Developer", "/Library/Developer/Xcode"}

function Basket.new(home)
	return setmetatable({home = home or "/Users", items = {}, order = {}}, Basket)
end

-- Checks a path is something a person could mean to throw away. Returns ok
-- and a reason for refusal.
function Basket.validate(path, home)
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return false, "Not an absolute path." end
	if path:find("/%.%./") or path:find("/%.%.$") or path:find("//", 1, true) then return false, "The path is not canonical." end
	local trimmed = path:gsub("/+$", "")
	if trimmed == "" then trimmed = "/" end
	for _, refused in ipairs(REFUSED) do
		if trimmed == refused then return false, "System location." end
	end
	if trimmed:match("^/Volumes/[^/]+$") or trimmed:match("^/System/Volumes/[^/]+$") then return false, "Mount point." end
	if trimmed:match("^/System/") then return false, "Protected macOS location." end
	for _, folder in ipairs(HOME_FOLDERS) do
		if trimmed == (home or "") .. folder then return false, "Standard folder in your home." end
	end
	return true
end

-- Adds an item {id, path, name, bytes, consequence, source}. Returns ok and a
-- refusal reason.
function Basket:add(item)
	local ok, reason = Basket.validate(item.path, self.home)
	if not ok then return false, reason end
	for _, path in ipairs(self.order) do
		-- A parent and its child would be counted and moved twice.
		if item.path:sub(1, #path + 1) == path .. "/" then return false, "Its folder is already marked." end
	end
	if not self.items[item.path] then table.insert(self.order, item.path) end
	self.items[item.path] = item
	for index = #self.order, 1, -1 do
		local path = self.order[index]
		if path:sub(1, #item.path + 1) == item.path .. "/" then
			self.items[path] = nil
			table.remove(self.order, index)
		end
	end
	return true
end

function Basket:remove(path)
	if not self.items[path] then return false end
	self.items[path] = nil
	for index, value in ipairs(self.order) do
		if value == path then table.remove(self.order, index); break end
	end
	return true
end

function Basket:contains(path) return self.items[path] ~= nil end
function Basket:count() return #self.order end
function Basket:clear() self.items, self.order = {}, {} end

function Basket:rows()
	local rows, bytes = {}, 0
	for _, path in ipairs(self.order) do
		local item = self.items[path]
		bytes = bytes + (item.bytes or 0)
		table.insert(rows, {id = path, path = path, name = item.name or path:match("([^/]+)$"),
			subtitle = item.source and (item.source .. " · " .. path) or path, bytes = item.bytes,
			size = Model.size(item.bytes), consequence = item.consequence or "Moves to the Trash. Put it back from the Trash in Finder."})
	end
	return rows, bytes
end

function Basket:summary()
	local rows, bytes = self:rows()
	if #rows == 0 then return "Nothing marked for cleanup" end
	return #rows .. (#rows == 1 and " item · " or " items · ") .. Model.size(bytes)
end

return Basket
