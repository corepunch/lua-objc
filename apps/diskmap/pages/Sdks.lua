local Format = require("apps.diskmap.helpers.Format")
local Sdks = require("apps.diskmap.helpers.Sdks")
local Discovery = require("apps.diskmap.services.Sdks")

-- The SDKs one installation holds (an Xcode, the Command Line Tools). Sizes
-- the discovery did not know are measured once the page is open.
local routes = {}

local SdksPage = {view = "pages/Sdks"}
routes.sdks = SdksPage

function SdksPage:init()
	self.service, self.rows, self.query = self.app.service, {}, ""
end

function SdksPage:focus(params)
	local row = require("apps.diskmap.models.Locations"):find(params.id)
	if not row then self.rows, self.measuring, self.resourceId, self.title = {}, false, nil, "SDKs"; return end
	self.resourceId = row.id
	self.root, self.title, self.query = row.path, row.name, ""
	self.rows = Discovery.discover(self.service, self.root)
	self.unknown = {}
	for _, sdk in ipairs(self.rows) do
		if sdk.bytes == nil then table.insert(self.unknown, sdk) end
	end
	self.measuring = #self.unknown > 0
	if self.active then self:activate() end
end

-- Sizes still being measured show one progress state in place of the list.
function SdksPage:data()
	local rows = self.measuring and {} or Sdks.filter(self.rows, self.query)
	for _, row in ipairs(rows) do row.reviewOnly = true; self:flow("Rows"):annotateReview(row) end
	return {lists = {rows = rows}, loading = {rows = self.measuring}, title = self.title,
		hidden = {noSdks = self.measuring or #rows > 0, rows = not self.measuring and #rows == 0}}
end

function SdksPage:markRow(_, _, row) self:flow("Rows"):toggleReview(row) end
function SdksPage:openRow(_, _, row) if row and row.path then self.app.show("folder", {path = row.path}) end end

function SdksPage:search(value) self.query = value or "" end

-- Leaving the page first drops the answer.
function SdksPage:location() return {id = self.resourceId} end

function SdksPage:activate()
	self.active = true
	if not self.measuring then return end
	local rows, slots, paths = self.rows, self.unknown, {}
	for _, sdk in ipairs(slots) do table.insert(paths, sdk.path) end
	self.service.measure(paths, function(sizes)
		if rows ~= self.rows or not self.active then return end
		for index, sdk in ipairs(slots) do
			sdk.bytes = sizes[index] or 0
			sdk.size = Format.size(sdk.bytes)
		end
		self.measuring = false
		self.app.refresh()
	end)
end

function SdksPage:deactivate() self.active, self.rows, self.measuring = false, {}, false end

function SdksPage:rendered(refs) self.refs = refs end

return routes
