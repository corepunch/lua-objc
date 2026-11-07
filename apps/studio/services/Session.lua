local Workspaces = require("apps.studio.Model")
local Session = {}
Session.__index = Session

function Session.open(storage, seed, id)
	return setmetatable({ storage = storage, workspace = Workspaces:open(id, seed, storage.load()) }, Session)
end

function Session:apply(changes)
	local files, err = self.workspace:prepare(changes)
	if not files then return nil, err end
	local ok
	ok, err = self.storage.save({ files = files, modelId = self.workspace.modelId })
	if not ok then return nil, err or "Could not save project" end
	return self.workspace:commit(files)
end

function Session:saveDrafts()
	local changes = self.workspace:pendingChanges()
	if #changes == 0 then return true end
	return self:apply(changes)
end

function Session:undo()
	local row = self.workspace
	if next(row.drafts) then return row:undo() end
	local previous = row.history[#row.history]
	if not previous then return nil, "Nothing to undo" end
	local ok, err = self.storage.save({ files = previous, modelId = row.modelId })
	if not ok then return nil, err end
	return row:undo()
end

function Session:setModel(value)
	local previous = self.workspace.modelId
	local ok, err = self.workspace:update({ modelId = value })
	if not ok then return nil, err end
	ok, err = self.storage.save({ files = self.workspace.files, modelId = value })
	if not ok then self.workspace:update({ modelId = previous }); return nil, err end
	return true
end

return Session
