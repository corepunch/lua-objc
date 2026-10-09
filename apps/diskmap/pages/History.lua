local OperationLog = require("apps.diskmap.helpers.OperationLog")

-- The action history: every move, deletion and owner command Diskmap
-- ran, read back from the operation log each time it is drawn.
local routes = {}

local History = {view = "pages/History"}
routes.history = History

function History:data()
	local service = self.app.service
	local rows = OperationLog.rows(service.operationLog())
	return {lists = {entries = rows}, hidden = {entries = #rows == 0, historyEmpty = #rows > 0}, subtitle = #rows == 0 and "Diskmap has not changed anything on this Mac yet."
		or (#rows .. (#rows == 1 and " action" or " actions") .. " · also written to ~/Library/Logs/Diskmap/operations.log")}
end

function History:rendered(refs) self.refs = refs end

return routes
