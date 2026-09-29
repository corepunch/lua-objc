_G.__headless = true
local t = require("TestKit")
local native = require("Git")
local Git = require("apps.studio.services.Git")

-- Studio records its project with the libgit2 module, never a git process.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/studio-git.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local workspace = root .. "/workspace"
local function write(path, content)
	local folder = (workspace .. "/" .. path):match("^(.*)/")
	os.execute("/bin/mkdir -p " .. folder)
	local file = io.open(workspace .. "/" .. path, "w")
	if not file then return nil, "cannot write " .. path end
	file:write(content); file:close()
	return true
end
-- The index order follows the file system's case sensitivity.
local function tracked(repo)
	local paths = repo:files()
	table.sort(paths)
	return table.concat(paths, ",")
end
local files = {
	["demo/playground/init.lua"] = "return require('demo.playground.Controller')\n",
	["demo/playground/views/Window.etlua"] = "<Window />\n",
}

t.assertEqual(Git.relativePath("demo/playground/views/Window.etlua"), "views/Window.etlua",
	"project paths are repository-relative")
t.expect(Git.relativePath("apps/studio/Model.lua") == nil, "other paths are not project files")

local git = assert(Git.open(native, workspace, write))
t.assertEqual(#git:history(), 0, "a new workspace has no history")
local first = assert(git:record(files, "Start project"))
t.assertEqual(#first, 40, "recording returns the commit id")
local repo = assert(native.open(workspace))
t.assertEqual(tracked(repo), "init.lua,views/Window.etlua", "the repository holds the project files")
t.assertEqual(repo:show("HEAD", "views/Window.etlua"), "<Window />\n", "files are committed with their content")
t.assertEqual(git:record(files, "Again"), false, "an unchanged project records nothing")
t.assertEqual(#git:history(), 1, "no empty commits")

files["demo/playground/views/Window.etlua"] = nil
files["demo/playground/Model.lua"] = "return {}\n"
local second = assert(git:record(files, "Replace window"))
t.assertEqual(tracked(repo), "Model.lua,init.lua", "files the project dropped are deleted")
t.expect(io.open(workspace .. "/views/Window.etlua") == nil, "deleted files leave the worktree")
local history = git:history()
t.assertEqual(#history, 2, "each change is one commit")
t.assertEqual(history[1].id, second, "history is newest first")
t.assertEqual(history[1].author, "Lua Studio", "Studio authors its commits")
t.assertEqual(#git:history(1), 1, "history can be limited")
git:close()

local reopened = assert(Git.open(native, workspace, write))
t.assertEqual(reopened:history()[1].id, second, "reopening keeps the history")
local ok, err = reopened:record({ ["../escape.lua"] = "" }, "Bad")
t.expect(ok == nil and err:find("Not a project path", 1, true), "paths outside the project are refused")
ok, err = Git.open(native, workspace, function() return nil, "disk full" end):record(files, "Fails")
t.expect(ok == nil and err == "disk full", "write failures are reported")
local blocked = root .. "/file"
assert(io.open(blocked, "w")):close()
ok, err = Git.open(native, blocked .. "/repo", write)
t.expect(ok == nil and type(err) == "string", "a repository that cannot be created is reported")
repo:close()
reopened:close()

-- The toolbar's Commit action reports the result in the status line.
local Controller = require("apps.studio.Controller")
local recorded = {}
local controller = setmetatable({
	model = { files = files },
	refs = { previewStatus = {} },
	git = { record = function(_, value, message)
		table.insert(recorded, message)
		if message == "fail" then return nil, "locked" end
		if message == "same" then return false end
		return value == files and "0123456789abcdef0123456789abcdef01234567"
	end },
}, Controller)
t.expect(controller:commitProject("Update project"), "commit records the model's files")
t.assertEqual(recorded[1], "Update project", "the commit message is passed through")
t.assertEqual(controller.refs.previewStatus.text, "Committed 0123456", "a commit shows its short id")
t.assertEqual(controller:commitProject("same"), false, "an unchanged project is not an error")
t.assertEqual(controller.refs.previewStatus.text, "No changes to commit", "an unchanged project says so")
t.expect(controller:commitProject("fail") == nil, "a failed commit is reported")
t.assertEqual(controller.refs.previewStatus.text, "Commit failed: locked", "the failure is shown")
controller.git, controller.gitError = nil, "no repository"
t.expect(controller:commitProject("x") == nil, "commit without a repository fails")
t.assertEqual(controller.refs.previewStatus.text, "Git unavailable: no repository", "the open error is shown")

local source = require("ui.xml").describeFile("apps/studio/views/Window.etlua", {
	sidebar = require("apps.studio.controllers.SidebarController").new({
		iconSize = 20, iconSlotWidth = 32, rowPadding = 8, expandedPadding = 12, collapsedPadding = 8,
		expandedWidth = 208, compactWidth = 184, collapsedWidth = 64,
	}):presentation(),
	preview = { device = "iPhone 16", zoom = "100%", runLabel = "Run" },
	chat = { status = "Ready", prompt = "Prompt", response = "Response", files = {}, suggestions = {} },
}).source
t.expect(source:find('title="Commit"[^>]*action="commitProject"') ~= nil, "the toolbar's Commit button commits")

os.execute("/bin/rm -rf " .. root)
os.exit(t.summary() and 0 or 1)
