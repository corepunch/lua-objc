local SheetPage = require("apps.diskmap.SheetPage")
local OperationLog = require("apps.diskmap.models.OperationLog")

-- The action history sheet: every move, deletion and owner command Diskmap
-- ran, read back from the operation log each time it is drawn.
local History = SheetPage.define({id = "history", view = "History", width = 640, height = 480})

function History.new(_, services)
	return setmetatable({services = services}, History)
end

function History:data()
	local service = self.services.service
	local rows = OperationLog.rows(type(service.operationLog) == "function" and service.operationLog() or {})
	return {lists = {entries = rows}, texts = {detail = #rows == 0 and "Diskmap has not changed anything on this Mac yet."
		or (#rows .. (#rows == 1 and " action" or " actions") .. " · also written to ~/Library/Logs/Diskmap/operations.log")}}
end

return History
