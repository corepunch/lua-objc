local ns = require("AppKit")
local Sheet = require("apps.diskmap.Sheet")
local xml = require("ui.xml")
local OperationLog = require("apps.diskmap.models.OperationLog")
local Controller = {}; Controller.__index = Controller

-- The action history sheet: every move, deletion and owner command Diskmap
-- ran, read back from the operation log.
function Controller.new(service)
	return setmetatable({service = service}, Controller)
end

function Controller:open(parent)
	self:close()
	local lines = type(self.service.operationLog) == "function" and self.service.operationLog() or {}
	local rows = OperationLog.rows(lines)
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/History.etlua", {
			detail = #rows == 0 and "Diskmap has not changed anything on this Mac yet."
				or (#rows .. (#rows == 1 and " action" or " actions") .. " · also written to ~/Library/Logs/Diskmap/operations.log"),
			actions = {done = function() self:close() end}}, ns)
	end, parent)
	if self.refs then self.refs.entries:replaceRows(rows) end
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

return Controller
