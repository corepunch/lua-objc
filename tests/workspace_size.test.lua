_G.__headless = true
local t = require("TestKit")

-- Space regressions become visible: a fresh source workspace stays under 100 MB.
local BUDGET = 100 * 1000 * 1000
local pipe = io.popen("git ls-files -z 2>/dev/null | xargs -0 stat -f '%z' 2>/dev/null")
local total, count = 0, 0
if pipe then
	for size in pipe:lines() do total = total + (tonumber(size) or 0); count = count + 1 end
	pipe:close()
end
if count > 0 then
	t.expect(total < BUDGET, string.format("tracked source is %.1f MB, under the 100 MB workspace budget", total / 1e6))
	t.expect(total < 0.8 * BUDGET, string.format("with headroom: %.1f MB of 100 MB", total / 1e6))
end

local function read(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local text = file:read("*a"); file:close()
	return text
end
local makefile = read("Makefile")
if makefile then
	t.expect(makefile:find("DEP_CACHE", 1, true) and makefile:find("cp -c", 1, true), "compiled dependencies are cached once and cloned into each worktree")
	t.expect(makefile:find("LIBGIT2_KEY", 1, true) and makefile:find("rev-parse HEAD", 1, true), "the cache is keyed by the pinned revision")
	t.expect(makefile:find("libgit2.mk", 1, true) and makefile:find("xcrun clang --version", 1, true), "and by the compiler inputs and version")
end
local script = read("scripts/workspace-size.sh")
if script then
	t.expect(script:find("worktree add", 1, true) and script:find("LIMIT_MB", 1, true), "a script measures a fresh worktree's incremental storage")
end
local doc = read("docs/workspaces.md")
if doc then t.expect(doc:find("100 MB", 1, true) and doc:find("--depth 1", 1, true), "the workspace policy is documented") end
os.exit(t.summary() and 0 or 1)
