local ns = require("AppKit")
local xml = require("ui.xml")
local Sheet = require("apps.diskmap.Sheet")
local Tour = require("apps.diskmap.models.Tour")
local Controller = {}; Controller.__index = Controller

-- Pages slide in from the side they come from: Continue brings the next one
-- in from the trailing edge, Back the previous one from the leading edge.
-- The system's push transition does the sliding.
local SLIDE = { forward = "trailing", backward = "leading" }

-- The welcome tour sheet: on start, after any access steps and while the
-- scan runs, until "Show this window on start" is turned off, and whenever
-- Help > Diskmap Tour opens it. Skip closes it at any page.
function Controller.new(service)
	return setmetatable({service = service, page = 1}, Controller)
end

local function call(service, name, ...)
	local fn = rawget(service, name)
	if type(fn) == "function" then return fn(...) end
end

-- On a real Mac only: the synthetic disk (no access probe) is for demos
-- and screenshots, which a tour would cover. The flag is stored inverted
-- so that a new install, with no flags, shows the tour.
function Controller:showOnStart() return call(self.service, "loadFlag", "hideTour") ~= true end
function Controller:setShowOnStart(show) call(self.service, "saveFlag", "hideTour", not show) end
function Controller:needed(disk)
	if type(rawget(self.service, "hasFullDiskAccess")) ~= "function" then return false end
	-- A storage alert needs a direct route to findings. The tour remains
	-- available from Help, and the person’s show-on-start choice is preserved.
	if disk and disk.totalKb and disk.totalKb > 0 and disk.freeKb and disk.freeKb / disk.totalKb < 0.1 then return false end
	return self:showOnStart()
end

function Controller:open(parent)
	if self.sheet or parent.attachedSheet then return false end
	self.page = 1
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/Tour.etlua", {pages = Tour.pages, showOnStart = self:showOnStart(), actions = {
			showOnStart = function() self:setShowOnStart(self.refs.showOnStart.state == 1) end,
			back = function() self:show(self.page - 1) end,
			next = function() self:next() end,
			goTo = function(page) self:show(page + 1) end,
			skip = function() self:finish() end,
		}}, ns)
	end, parent)
	self:show(1)
	return true
end

function Controller:show(index)
	if not self.sheet then return end
	local previous = self.page
	self.page = math.max(1, math.min(index, #Tour.pages))
	if previous ~= self.page then
		ns._pushTransition(self.refs.pages, self.page > previous and SLIDE.forward or SLIDE.backward)
	end
	for _, page in ipairs(Tour.pages) do self.refs["page_" .. page.index].hidden = page.index ~= self.page end
	self.refs.dots.currentPage = self.page - 1
	self.refs.back.hidden = self.page == 1
	self.refs.next.title = self.page == #Tour.pages and "Start Using Diskmap" or "Continue"
end

-- Continue, or Start Using Diskmap on the last page.
function Controller:next()
	if self.page == #Tour.pages then self:finish() else self:show(self.page + 1) end
end

function Controller:finish()
	if not self.sheet then return end
	ns.dismiss(self.sheet)
	self.sheet, self.refs = nil, nil
end

return Controller
