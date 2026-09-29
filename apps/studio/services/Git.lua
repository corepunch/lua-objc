-- Keeps the playground project in a Git repository, one commit per recorded
-- version. The repository is the libgit2 `Git` module (src/plugins/git): iPadOS
-- cannot run a git executable. Studio owns the repository's worktree; it holds
-- exactly the project's files, rewritten from the model before each commit.
local Git = {}
Git.__index = Git

local PREFIX = "demo/playground/"
local AUTHOR = { name = "Lua Studio", email = "studio@lua-objc.local" }

-- `native` is require("Git"); `root` the repository folder's absolute path;
-- `write(path, content)` saves a worktree-relative file, creating folders.
function Git.open(native, root, write)
	local repo = native.open(root)
	if not repo then
		local err
		repo, err = native.init(root)
		if not repo then return nil, err end
	end
	return setmetatable({ repo = repo, write = write }, Git)
end

-- Model paths (demo/playground/...) are the repository's root-relative paths.
function Git.relativePath(path)
	return path:sub(1, #PREFIX) == PREFIX and path:sub(#PREFIX + 1) or nil
end

-- Writes `files` into the worktree, deletes tracked files they no longer
-- contain, and commits. Returns the commit id, false when nothing changed,
-- or nil and an error.
function Git:record(files, message)
	local present = {}
	for path, source in pairs(files) do
		local relative = Git.relativePath(path)
		if not relative then return nil, "Not a project path: " .. tostring(path) end
		present[relative] = true
		local ok, err = self.write(relative, source)
		if not ok then return nil, err or "Could not write " .. relative end
	end
	local workdir = self.repo:workdir()
	for _, path in ipairs(assert(self.repo:files())) do
		if not present[path] then os.remove(workdir .. path) end
	end
	local ok, err = self.repo:add()
	if not ok then return nil, err end
	local status
	status, err = self.repo:status()
	if not status then return nil, err end
	local staged = false
	for _, entry in ipairs(status) do
		if entry.index then staged = true end
	end
	if not staged then return false end
	return self.repo:commit(message, AUTHOR)
end

function Git:history(limit)
	return self.repo:log({ limit = limit })
end

function Git:close()
	self.repo:close()
end

return Git
