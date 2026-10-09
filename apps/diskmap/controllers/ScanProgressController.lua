local ns = require("AppKit")
local xml = require("ui.xml")
local Controller = {}; Controller.__index = Controller

local VIEW = "apps/diskmap/views/sheets/ScanProgress.etlua"
-- The sheet keeps this margin inside a narrow window.
local INSET = 80

-- The one place a running scan shows: a small sheet with a progress bar,
-- the location being measured, and Stop. The sheet is rendered once; each
-- scan tick sets the bar's value and the status text on the views it keeps,
-- and nothing is rendered again. Pages say nothing about the scan; they are
-- drawn when it finishes. `scan` is the app's services/Scan.
function Controller.new(scan)
	return setmetatable({scan = scan}, Controller)
end

-- Opens the sheet over `parent`, or shows the newest numbers when it is open.
function Controller:show(parent)
	if not self.sheet then
		local actions = {stop = function() self.scan:cancel() end}
		self.sheet, self.refs = ns.presentSheet(function()
			local sheet, refs = xml.renderFile(VIEW, {actions = actions}, ns)
			local width = parent.size.width - INSET
			if width > 0 and sheet.size.width > width then sheet:resize(width, sheet.size.height) end
			return sheet, refs
		end, {parent = parent})
	end
	self:update()
end

-- A scan without the disk's used size has a bar of unknown length.
function Controller:update()
	local refs = self.refs
	if not refs then return end
	local fraction = self.scan:fraction()
	refs.scanBar.indeterminate = fraction == nil
	refs.scanBar.doubleValue = fraction or 0
	refs.scanStatus.text = self.scan.status
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

return Controller
