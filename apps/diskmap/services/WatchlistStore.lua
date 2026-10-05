local Watchlist = require("apps.diskmap.models.Watchlist")
local WatchlistStore = {}; WatchlistStore.__index = WatchlistStore

-- Watched locations across launches. Catalog resources take their size from
-- each finished scan; watched folders are measured right after it. Every
-- change is saved at once, and `changed()` refreshes the sidebar and page.
function WatchlistStore.new(model, service, changed)
	local load = service.loadWatchlist
	return setmetatable({model = model, service = service, changed = changed,
		list = Watchlist:restore(load())}, WatchlistStore)
end

function WatchlistStore:rows() return self.list:rows() end
function WatchlistStore:find(key) return self.list:find(key) end

function WatchlistStore:save()
	local save = self.service.saveWatchlist
	return save(self.list:encode())
end

-- `entry` is {kind = "resource", id} or {kind = "folder", path, name}.
function WatchlistStore:toggle(entry)
	local ok, watching = self.list:toggle(entry)
	if not ok then self.service.showError("Cannot favorite this location", watching and watching.message or ""); return false end
	if watching then
		self.list:sync()
		if entry.kind == "folder" then self:measure({self.list:find(Watchlist.key(entry))}) end
	end
	if not self:save() then self.service.showError("Favorites could not be saved", "Check that your Library folder is writable.") end
	self.changed()
	return true
end

-- The watchlist supplies both quick shortcuts and size tracking.
function WatchlistStore:menuItem(entry)
	local watching = self.list:has(Watchlist.key(entry))
	return {title = watching and "Remove from Favorites" or "Add to Favorites", systemImage = watching and "star.slash" or "star",
		action = function() self:toggle(entry) end}
end

function WatchlistStore:measure(entries)
	local measure = self.service.measure
	if #entries == 0 then return end
	local exists = self.service.exists
	local paths = {}
	local scan = self.model.scan
	for _, entry in ipairs(entries) do table.insert(paths, entry.path) end
	measure(paths, function(sizes)
		if self.closed or self.model.scan ~= scan then return end
		for index, entry in ipairs(entries) do
			local present = exists(entry.path)
			self.list:record(Watchlist.key(entry), sizes[index], present)
		end
		self:save()
		self.changed()
	end)
end

function WatchlistStore:dispose() self.closed = true end

-- After a finished scan: this session's sizes replace what is stored, so
-- the next launch compares with how this one ended.
function WatchlistStore:scanFinished()
	self.list:sync()
	self:save()
	self:measure(self.list:folders())
	self.changed()
end

return WatchlistStore
