local App = require("App")

local Recent = {}
Recent.__index = Recent

function Recent.new(opts)
	opts = opts or {}
	local state = setmetatable({
		store = App.recentStore(opts.key or "ide", {
			storageRoot = opts.storageRoot,
			limit = opts.limit or 12,
		}),
	}, Recent)
	return state
end

function Recent:list()
	return self.store:list()
end

function Recent:files()
	return self.store:itemsOfKind("file")
end

function Recent:folders()
	return self.store:itemsOfKind("folder")
end

function Recent:recordFile(path, title)
	return self.store:recordFile(path, title)
end

function Recent:recordFolder(path, title)
	return self.store:recordFolder(path, title)
end

function Recent:clear()
	return self.store:clear()
end

return Recent
