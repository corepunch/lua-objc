local Watchlist = require("apps.diskmap.models.Watchlist")
local Controller = {}; Controller.__index = Controller

-- Watched locations across launches. Catalog resources take their size from
-- each finished scan; watched folders are measured right after it. Every
-- change is saved at once, and `changed()` refreshes the sidebar and page.
function Controller.new(model, service, changed)
	local load = rawget(service, "loadWatchlist")
	return setmetatable({model = model, service = service, changed = changed,
		list = Watchlist.new(model, load and load() or {})}, Controller)
end

function Controller:rows() return self.list:rows() end
function Controller:find(key) return self.list:find(key) end

function Controller:save()
	local save = rawget(self.service, "saveWatchlist")
	return not save or save(self.list:encode())
end

-- `entry` is {kind = "resource", id} or {kind = "folder", path, name}.
function Controller:toggle(entry)
	local ok, watching = self.list:toggle(entry)
	if not ok then self.service.showError("Cannot watch this location", watching and watching.message or ""); return false end
	if watching then
		self.list:sync()
		if entry.kind == "folder" then self:measure({self.list:find(Watchlist.key(entry))}) end
	end
	if not self:save() then self.service.showError("Watched locations could not be saved", "Check that your Library folder is writable.") end
	self.changed()
	return true
end

-- The row-menu item that watches or stops watching `entry`.
function Controller:menuItem(entry)
	local watching = self.list:has(Watchlist.key(entry))
	return {title = watching and "Stop Watching" or "Watch", systemImage = watching and "eye.slash" or "eye",
		action = function() self:toggle(entry) end}
end

function Controller:measure(entries)
	local measure = rawget(self.service, "measure")
	if not measure or #entries == 0 then return end
	local exists = rawget(self.service, "exists")
	local paths = {}
	for _, entry in ipairs(entries) do table.insert(paths, entry.path) end
	measure(paths, function(sizes)
		for index, entry in ipairs(entries) do
			local present = not exists or exists(entry.path)
			self.list:record(Watchlist.key(entry), sizes[index], present)
		end
		self:save()
		self.changed()
	end)
end

-- After a finished scan: this session's sizes replace what is stored, so
-- the next launch compares with how this one ended.
function Controller:scanFinished()
	self.list:sync()
	self:save()
	self:measure(self.list:folders())
	self.changed()
end

return Controller
