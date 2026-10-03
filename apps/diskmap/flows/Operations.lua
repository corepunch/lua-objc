local Flow = require("data.flow")
local OperationLog = require("apps.diskmap.helpers.OperationLog")
local Operations = Flow:extend()

-- Every destructive action calls this exactly once, including failures.
function Operations:log(action, ok, bytes, target, detail)
	return self.app.service.logOperation(OperationLog.format({action = action, ok = ok, bytes = bytes, target = target, detail = detail}))
end

return Operations
