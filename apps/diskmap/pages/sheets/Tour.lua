local Provider = require("apps.diskmap.services.Provider")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")
local Tour = require("apps.diskmap.helpers.Tour")

-- The welcome tour sheet: on start, after any access steps and while the
-- scan runs, until "Show this window on start" is turned off, and whenever
-- Help > Diskmap Tour opens it. Skip closes it at any page. Pages slide in
-- from the side they come from: Continue brings the next one in from the
-- trailing edge, Back the previous one from the leading edge.
local routes = {}

local TourSheet = SheetRoute.extend({view = "sheets/Tour", width = 580, height = 540})
routes.tour = TourSheet

function TourSheet:init()
	self.service, self.page = self.app.service, 1
end

local function call(service, name, ...)
	local fn = Provider.offers(service, name)
	if type(fn) == "function" then return fn(...) end
end

-- On a real Mac only: the synthetic disk (no access probe) is for demos
-- and screenshots, which a tour would cover. The flag is stored inverted
-- so that a new install, with no flags, shows the tour.
function TourSheet:showOnStart() return call(self.service, "loadFlag", "hideTour") ~= true end
function TourSheet:setShowOnStart(show) call(self.service, "saveFlag", "hideTour", not show) end
function TourSheet:toggleShowOnStart() self:setShowOnStart(not self:showOnStart()) end

function TourSheet:needed(disk)
	if type(Provider.offers(self.service, "hasFullDiskAccess")) ~= "function" then return false end
	-- A storage alert needs a direct route to findings. The tour remains
	-- available from Help, and the person’s show-on-start choice is preserved.
	if disk and disk.totalKb and disk.totalKb > 0 and disk.freeKb and disk.freeKb / disk.totalKb < 0.1 then return false end
	return self:showOnStart()
end

function TourSheet:open(parent)
	if self.sheet or parent.attachedSheet then return false end
	self.page = 1
	SheetRoute.open(self, parent)
	return true
end

function TourSheet:data()
	local last = self.page == #Tour.pages
	return {pages = Tour.pages, current = self.page, showOnStart = self:showOnStart(),
		texts = {next = last and "Start Using Diskmap" or "Continue"}, hidden = {back = self.page == 1}}
end

function TourSheet:show(index)
	if not self.sheet then return end
	local previous = self.page
	self.page = math.max(1, math.min(index, #Tour.pages))
	if previous ~= self.page then self.slide = {id = "pages", edge = self.page > previous and "trailing" or "leading"} end
	self:draw()
end

function TourSheet:back() self:show(self.page - 1) end
function TourSheet:goTo(page) self:show(page + 1) end

-- Continue, or Start Using Diskmap on the last page.
function TourSheet:next()
	if self.page == #Tour.pages then self:close() else self:show(self.page + 1) end
end

return routes
