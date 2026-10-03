local Model = require("data.model")
local Flow = require("data.flow")
local Format = require("apps.diskmap.helpers.Format")
local Operations = require("apps.diskmap.flows.Operations")
local EmptyTrash = Flow:extend()

function EmptyTrash:execute()
	local service, home = self.app.service, Model.db.home
	local before = service.diskSpace(home)
	local called, ok, detail = pcall(service.emptyTrash)
	if not called then detail, ok = tostring(ok), false end
	local after = service.diskSpace(home)
	local freed = before and after and (after.freeKb - before.freeKb) * 1024 or nil
	Operations(self):log("Empty Trash", ok == true, math.max(0, freed or 0), "~/.Trash", detail)
	return ok == true, detail, freed
end

function EmptyTrash:run()
	if not self.app.service.confirmAction("Empty Trash",
		"Permanently removes everything in the Trash, including items you moved there before. This cannot be undone.") then return false end
	local ok, detail, freed = self:execute()
	local status
	if ok and freed and freed > 0 then status = "Emptied the Trash. macOS now reports " .. Format.size(freed) .. " more free space."
	elseif ok then status = "Emptied the Trash. Free space has not changed yet; local snapshots may still hold the blocks."
	else
		status = "The Trash could not be emptied."
		self.app.service.showError("Could not empty Trash", detail or "Check permissions.")
	end
	if ok then self.app.removed(Model.db.home .. "/.Trash") end
	return ok, status
end

return EmptyTrash
