local DataModel = require("data.model")
local Filesystem = require("apps.diskmap.models.Filesystem")

-- The macOS Folders page. Sizes of the locations no scan resource covers are
-- measured once per scan: Inventory clears `model.folderSizes` when a new
-- scan begins, so a draw after the scan that finds them gone measures again.
-- Until then (and while the scan runs) the rows say "Not measured"; the
-- page's own measurement is the page-level `computing` spinner.
local FilesystemPage = DataModel.define({})

function FilesystemPage.new(_, services)
	return setmetatable({services = services, storage = services.model}, FilesystemPage)
end

function FilesystemPage:waiting()
	return not (self.storage.folderSizes or self.storage.scan.running) and self.services.service.measure ~= nil
end

function FilesystemPage:rendered()
	local storage, service = self.storage, self.services.service
	if self.measuring or not self:waiting() then return end
	local paths = Filesystem.pending(storage)
	self.measuring = true
	service.measure(paths, function(sizes, states)
		self.measuring = false
		local found = {}
		for index, path in ipairs(paths) do
			found[path] = {bytes = sizes[index] or 0, state = states and states[index] or "measured"}
		end
		storage.folderSizes = found
		self.services.refresh()
	end)
end

-- Each row's Finder and Diskmap buttons are named by their location.
function FilesystemPage:data(state)
	local data = Filesystem.presentation(self.storage, self.storage.folderSizes, state.fullDiskAccess, state.query)
	data.query = state.query or ""
	if self:waiting() then data.computing = "Measuring folders…" end
	data.handlers = {}
	for _, area in ipairs(data.areas) do
		for index, row in ipairs(area.rows) do
			local key = area.id .. "_" .. index
			data.handlers["reveal_" .. key] = function() self.services.service.reveal(row.path) end
			if row.resource then data.handlers["open_" .. key] = function() self.services.open(row.resource) end end
		end
	end
	return data
end

return FilesystemPage
