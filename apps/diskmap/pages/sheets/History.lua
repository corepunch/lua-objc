local OperationLog = require("apps.diskmap.helpers.OperationLog")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")

-- The action history sheet: every move, deletion and owner command Diskmap
-- ran, read back from the operation log each time it is drawn.
local routes = {}

local History = SheetRoute.extend({view = "sheets/History", width = 640, height = 480})
routes.history = History

function History:data()
	local service = self.app.service
	local rows = OperationLog.rows(type(service.operationLog) == "function" and service.operationLog() or {})
	return {lists = {entries = rows}, texts = {detail = #rows == 0 and "Diskmap has not changed anything on this Mac yet."
		or (#rows .. (#rows == 1 and " action" or " actions") .. " · also written to ~/Library/Logs/Diskmap/operations.log")}}
end

return routes
