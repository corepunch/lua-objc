local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Categories = require("apps.diskmap.helpers.Categories")
local Constraints = require("apps.diskmap.helpers.Constraints")

-- Locations the person watches across launches: a catalog resource (a
-- category, SDKs, macOS installers) or any folder, the store's `watchlist`
-- table keyed by `key`. Each entry persists as {kind, id | path, name,
-- bytes, measuredAt}, where `bytes` is the size the previous session ended
-- with. That stored size is this session's baseline, so the change shown is
-- "since you last had Diskmap open", like Finder's Favorites remembering
-- places but with the size they had. This session's sizes are the store's
-- `watchSizes`, by key.
local Watchlist = Model:extend("watchlist", {primaryKey = "key"})

-- Changes smaller than this read as unchanged: allocation moves by a few
-- blocks whenever an app touches its folder.
Watchlist.threshold = 1e6

function Watchlist.key(entry)
	return entry.kind == "resource" and ("resource:" .. entry.id) or ("folder:" .. entry.path)
end

local function validate(entry)
	return Constraints.evaluate("watch", {entry = entry,
		row = type(entry) == "table" and entry.id and Locations:find(entry.id) or nil})
end

local function sizes() return Model.db.watchSizes end

-- Fills the store with `entries` from storage; invalid, duplicate or retired
-- resources are dropped, as Keep drops ids the catalog no longer has.
function Watchlist:restore(entries)
	Model.db.watchlist, Model.db.watchSizes = {}, {}
	for _, entry in ipairs(entries or {}) do
		if validate(entry) and not self:find(Watchlist.key(entry)) then self:insert(entry) end
	end
	return self
end

function Watchlist:insert(entry)
	local row = entry.kind == "resource" and Locations:find(entry.id)
	return self:create({key = Watchlist.key(entry), kind = entry.kind, id = entry.id, path = entry.path,
		name = row and row.name or entry.name or (entry.path and entry.path:match("([^/]+)/*$")) or entry.path,
		bytes = tonumber(entry.bytes), measuredAt = tonumber(entry.measuredAt)})
end

function Watchlist:has(key) return self:find(key) ~= nil end

-- Adds or removes a watch; returns true and whether it is now watched.
function Watchlist:toggle(entry)
	local ok, err = validate(entry)
	if not ok then return false, err end
	local key = Watchlist.key(entry)
	local stored = self:find(key)
	if not stored then self:insert(entry); return true, true end
	stored:delete()
	sizes()[key] = nil
	return true, false
end

-- Watched folders that need measuring after a scan; catalog resources are
-- measured by the scan itself.
function Watchlist:folders()
	return self:select({kind = "folder"})
end

-- A folder's size this session. `exists = false` marks it missing.
function Watchlist:record(key, bytes, exists, time)
	if not self:find(key) then return end
	sizes()[key] = exists == false and {missing = true} or {bytes = bytes, time = time or os.time()}
end

-- Takes catalog resources' sizes from the finished scan. Only complete
-- measurements count, so an interrupted scan never looks like shrinkage.
function Watchlist:sync(time)
	for _, entry in ipairs(self:select({kind = "resource"})) do
		local row = Categories.row(entry.id)
		if row and row.status == "complete" and row.bytes then
			sizes()[entry.key] = {bytes = row.bytes, time = time or os.time()}
		end
	end
end

local function day(time)
	return os.date("%b", time) .. " " .. tonumber(os.date("%d", time))
end

-- The change since the previous session: signed bytes and its wording, or
-- nil while either side is unknown.
function Watchlist:change(key)
	local entry, current = self:find(key), sizes()[key]
	if not entry or not current or not current.bytes or not entry.bytes then return nil end
	local delta = current.bytes - entry.bytes
	local since = entry.measuredAt and (" since " .. day(entry.measuredAt)) or " since last time"
	if math.abs(delta) < Watchlist.threshold then return 0, "No change" .. since end
	return delta, Format.size(math.abs(delta)) .. (delta > 0 and " more" or " less") .. since
end

-- One row per watch for the sidebar and the Watched page.
function Watchlist:rows()
	local rows = {}
	for _, entry in ipairs(self:all()) do
		local key = entry.key
		local current = sizes()[key] or {}
		local resource = entry.kind == "resource" and Categories.row(entry.id)
		local row = {key = key, id = "watched:" .. key, kind = entry.kind, resourceId = entry.id,
			name = entry.name, path = entry.path or (resource and resource.path),
			icon = resource and resource.icon or "folder.fill", color = resource and resource.color or "systemBlue"}
		row.bytes = current.bytes or entry.bytes
		row.calculating = resource and resource.calculating or false
		row.missing = current.missing == true
		row.delta, row.changeText = self:change(key)
		if row.missing then row.size, row.changeText = "Missing", "This folder no longer exists"
		else row.size = row.bytes and Format.size(row.bytes) or "Not measured" end
		row.changeText = row.changeText or (current.bytes and "Measured for the first time" or "Waiting for a measurement")
		table.insert(rows, row)
	end
	return rows
end

-- What to store: this session's size becomes the next session's baseline.
function Watchlist:encode()
	local list = {}
	for _, entry in ipairs(self:all()) do
		local current = sizes()[entry.key] or {}
		table.insert(list, {kind = entry.kind, id = entry.id, path = entry.path, name = entry.name,
			bytes = current.bytes or entry.bytes, measuredAt = current.bytes and current.time or entry.measuredAt})
	end
	return list
end

return Watchlist
