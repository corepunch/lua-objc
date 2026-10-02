local SheetPage = require("apps.diskmap.SheetPage")
local Core = require("apps.diskmap.Model")

-- The one place a running scan shows: a small window with a progress bar that
-- fills as bytes are measured against the bytes the disk reports as used, the
-- location being measured, and Stop. Pages say nothing about the scan; they
-- are drawn when it finishes.
local ScanProgress = SheetPage.define({id = "scanProgress", view = "sheets/ScanProgress", width = 440, height = 168})

function ScanProgress.new(_, services)
	return setmetatable({services = services}, ScanProgress)
end

-- Measured over used, held under 1 until the scan says it is done; nil while
-- the disk's used size is not known, which draws a bar of unknown length.
function ScanProgress:fraction()
	local disk = self.services.scanDisk()
	local used = disk and disk.totalKb and disk.freeKb and (disk.totalKb - disk.freeKb) * 1024
	if not used or used <= 0 then return nil end
	return math.min(Core.total(self.services.model) / used, 0.99)
end

function ScanProgress:data()
	local fraction = self:fraction()
	return {fraction = fraction or 0, indeterminate = fraction == nil, status = self.services.scanStatus()}
end

-- Opens the window, or shows the newest numbers when it is open.
function ScanProgress:show(parent)
	if self.sheet then self:draw() else self:open(parent) end
end

function ScanProgress:stop()
	self.services.cancelScan()
end

return ScanProgress
