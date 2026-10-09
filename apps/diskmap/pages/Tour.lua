local Tour = require("apps.diskmap.helpers.Tour")

-- The welcome tour page: on start, after any access steps and while the
-- scan runs, until "Show this window on start" is turned off, and whenever
-- Help > Diskmap Tour opens it. Skip returns to Overview at any step.
local routes = {}

local TourPage = {view = "pages/Tour"}
routes.tour = TourPage

function TourPage:init()
	self.service, self.page = self.app.service, 1
end

-- On a real Mac only: the synthetic disk (no access probe) is for demos
-- and screenshots, which a tour would cover. The flag is stored inverted
-- so that a new install, with no flags, shows the tour.
function TourPage:showOnStart() return self.service.loadFlag("hideTour") ~= true end
function TourPage:setShowOnStart(show) self.service.saveFlag("hideTour", not show) end
function TourPage:toggleShowOnStart() self:setShowOnStart(not self:showOnStart()) end

function TourPage:needed(disk)
	if self.service.hasFullDiskAccess() == nil then return false end
	-- A storage alert needs a direct route to findings. The tour remains
	-- available from Help, and the person’s show-on-start choice is preserved.
	if disk and disk.totalKb and disk.totalKb > 0 and disk.freeKb and disk.freeKb / disk.totalKb < 0.1 then return false end
	return self:showOnStart()
end

function TourPage:focus(params) self.page = math.max(1, math.min(tonumber(params.step) or 1, #Tour.pages)) end
function TourPage:location() return {step = self.page} end
function TourPage:deactivate() self.refs = nil end
function TourPage:close() self.app.show("overview") end

function TourPage:data()
	local last = self.page == #Tour.pages
	return {pages = Tour.pages, current = self.page, showOnStart = self:showOnStart(),
		texts = {next = last and "Start Using Diskmap" or "Continue"}, hidden = {back = self.page == 1}}
end

function TourPage:show(index)
	self.page = math.max(1, math.min(index, #Tour.pages))
	self.app.refresh()
end

function TourPage:back() self:show(self.page - 1) end
function TourPage:goTo(page) self:show(page + 1) end

-- Continue, or Start Using Diskmap on the last page.
function TourPage:next()
	if self.page == #Tour.pages then self:close() else self:show(self.page + 1) end
end

function TourPage:rendered(refs) self.refs = refs end

return routes
