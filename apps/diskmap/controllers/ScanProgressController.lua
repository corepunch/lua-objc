local ns = require("AppKit")
local xml = require("ui.xml")
local Sheet = require("apps.diskmap.Sheet")
local Controller = {}; Controller.__index = Controller

local VIEW = "apps/diskmap/views/sheets/ScanProgress.etlua"

-- The one place a running scan shows: a small window with a progress bar,
-- the location being measured, and Stop. The window is rendered once; each
-- scan tick sets the bar's value and the status text on the views it keeps,
-- and nothing is rendered again. Pages say nothing about the scan; they are
-- drawn when it finishes. `scan` is the app's models/Scan.
function Controller.new(scan)
	return setmetatable({scan = scan}, Controller)
end

-- Opens the window, or shows the newest numbers when it is open.
function Controller:show(parent)
	if not self.sheet then
		local actions = {stop = function() self.scan:cancel() end}
		self.sheet, self.refs = Sheet.present(function() return xml.renderFile(VIEW, {actions = actions}, ns) end, parent)
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
