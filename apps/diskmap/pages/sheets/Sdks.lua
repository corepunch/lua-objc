local Format = require("apps.diskmap.helpers.Format")
local Sdks = require("apps.diskmap.helpers.Sdks")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")

-- The SDKs one installation holds (an Xcode, the Command Line Tools). Sizes
-- the discovery did not know are measured once the sheet is up.
local routes = {}

local SdksSheet = SheetRoute.extend({view = "sheets/Sdks", width = 620, height = 480})
routes.sdks = SdksSheet

function SdksSheet:init()
	self.service, self.rows, self.query = self.app.service, {}, ""
end

function SdksSheet:open(parent, row)
	self.root, self.title, self.query = row.path, row.name, ""
	self.rows = Sdks.discover(self.service, self.root)
	self.unknown = {}
	for _, sdk in ipairs(self.rows) do
		if sdk.bytes == nil then table.insert(self.unknown, sdk) end
	end
	self.measuring = #self.unknown > 0 and type(self.service.measure) == "function"
	SheetRoute.open(self, parent)
end

-- Sizes still being measured show one progress state in place of the list.
function SdksSheet:data()
	local rows = self.measuring and {} or Sdks.filter(self.rows, self.query)
	return {lists = {rows = rows}, loading = {rows = self.measuring}, texts = {title = self.title,
		status = self.measuring and "Measuring SDKs…" or #rows == 0 and "No matching SDKs."
			or (#rows .. (#rows == 1 and " SDK" or " SDKs"))}}
end

function SdksSheet:search(value) self.query = value or "" end

-- Closing the sheet first drops the answer.
function SdksSheet:activate()
	if not self.measuring then return end
	local rows, slots, paths = self.rows, self.unknown, {}
	for _, sdk in ipairs(slots) do table.insert(paths, sdk.path) end
	self.service.measure(paths, function(sizes)
		if rows ~= self.rows or not self.sheet then return end
		for index, sdk in ipairs(slots) do
			sdk.bytes = sizes[index] or 0
			sdk.size = Format.size(sdk.bytes)
		end
		self.measuring = false
		self:draw()
	end)
end

function SdksSheet:deactivate() self.rows, self.measuring = {}, false end

return routes
