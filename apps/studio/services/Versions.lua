-- Keeps the playground project's versions in a Git repository, one commit per
-- recorded version. The repository is the libgit2 `Git` module
-- (src/plugins/git): iPadOS cannot run a git executable. Studio owns the
-- worktree; it holds exactly the project's files, rewritten from the model
-- before each commit.
local Versions = {}
Versions.__index = Versions

local PREFIX = "demo/playground/"
local AUTHOR = { name = "Lua Studio", email = "studio@lua-objc.local" }

-- `git` is require("Git"); `root` the repository folder's absolute path;
-- `write(path, content)` saves a worktree-relative file, creating folders.
-- Opens the repository at root, creating it on first use.
function Versions.open(git, root, write)
	local repo, err = git.open(root)
	if not repo then repo, err = git.init(root) end
	if not repo then return nil, err end
	return setmetatable({ repo = repo, write = write }, Versions)
end

-- Model paths (demo/playground/...) are the repository's root-relative paths.
function Versions.relativePath(path)
	return path:sub(1, #PREFIX) == PREFIX and path:sub(#PREFIX + 1) or nil
end

-- Writes `files` into the worktree, deletes tracked files they no longer
-- contain, and commits. Returns the commit id, false when nothing changed,
-- or nil and an error.
function Versions:record(files, message)
	local present = {}
	for path, source in pairs(files) do
		local relative = Versions.relativePath(path)
		if not relative then return nil, "Not a project path: " .. tostring(path) end
		present[relative] = true
		local ok, err = self.write(relative, source)
		if not ok then return nil, err or "Could not write " .. relative end
	end
	local tracked, err = self.repo:files()
	if not tracked then return nil, err end
	local workdir = self.repo:workdir()
	for _, path in ipairs(tracked) do
		if not present[path] then os.remove(workdir .. path) end
	end
	local ok
	ok, err = self.repo:add()
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
