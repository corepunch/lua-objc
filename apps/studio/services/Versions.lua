-- Records the project's actual Documents folder through libgit2. Workspace
-- owns persistence; Git stages that same source alongside the project metadata.
local Versions = {}
Versions.__index = Versions

local AUTHOR = { name = "Lua Studio", email = "studio@lua-objc.local" }

-- `git` is require("Git"); `root` is the project's absolute folder path.
-- Opens the repository at root, creating it on first use.
function Versions.open(git, root)
	local repo, err = git.open(root)
	if not repo then repo, err = git.init(root) end
	if not repo then return nil, err end
	return setmetatable({ repo = repo }, Versions)
end

-- Returns the commit id, false when unchanged, or nil and an error.
function Versions:record(message)
	local ok, err = self.repo:add()
	if not ok then return nil, err end
	local status
	status, err = self.repo:status()
	if not status then return nil, err end
	for _, entry in ipairs(status) do
		if entry.index then return self.repo:commit(message, AUTHOR) end
	end
	return false
end

-- Recorded versions, newest first: {id, shortId, summary, time, ...}.
function Versions:log(limit)
	return self.repo:log({ limit = limit })
end

function Versions:close()
	self.repo:close()
end

return Versions
