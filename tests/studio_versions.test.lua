_G.__headless = true
local t = require("TestKit")
local Git = require("Git")
local Versions = require("apps.studio.services.Versions")

-- Studio records its project with the libgit2 module, never a git process.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/studio-git.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local ns = require("ns")
local Workspace = require("apps.studio.services.Workspace")
local function read(path)
	local file = io.open(path)
	if not file then return nil end
	local content = file:read("a"); file:close()
	return content
end
local function write(path, content)
	local folder = (root .. "/" .. path):match("^(.*)/")
	os.execute("/bin/mkdir -p " .. folder)
	local file = io.open(root .. "/" .. path, "w")
	if not file then return nil, "cannot write " .. path end
	file:write(content); file:close()
	return true
end
local documentNS = {
	_documentRead = function(path) return read(root .. "/" .. path) end,
	_documentWrite = write,
	_documentExists = function(path)
		local file = io.open(root .. "/" .. path, "rb")
		if not file then return false end
		file:close()
		return true
	end,
	_documentWriteData = write,
	_documentPath = function(path) return root .. "/" .. path end,
	_readFile = function(path) return read(path) end,
	_jsonEncode = ns._jsonEncode,
	json_parse = ns.json_parse,
}
local workspace = Workspace.open(documentNS, read, Git, "HabitTracker")
local function save(files)
	return workspace.storage.save({ files = files, model = "openrouter/free" })
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

t.assertEqual(workspace.root, root .. "/HabitTracker", "Git uses the actual project folder")
t.assertEqual(read(workspace.root .. "/AppIcon.png"), read("apps/studio/ProjectIcons/rocket-sketch.png"),
	"first launch installs the default rocket sketch icon")
assert(save(files))
assert(workspace.localStorage.set("habits", '{"completed":true}'))
assert(write("HabitTracker/notes.txt", "Keep my project notes"))
local versions = assert(Versions.open(Git, workspace.root))
t.assertEqual(#versions:log(), 1, "opening materializes the project with an initial commit")
local first = assert(versions:record("Start project"))
t.assertEqual(#first, 40, "recording returns the commit id")
local repo = assert(Git.open(workspace.root))
t.assertEqual(tracked(repo), ".gitignore,AppIcon.png,ProjectIcons/desk.png,ProjectIcons/rocket-sketch.png,ProjectIcons/rocket.png,init.lua,notes.txt,project.lua,views/Window.etlua", "source, metadata and all project icons are tracked; data and settings are ignored")
t.assertEqual(repo:show("HEAD", "views/Window.etlua"), "<Window />\n", "files are committed with their content")
t.assertEqual(versions:record("Again"), false, "an unchanged project records nothing")
t.assertEqual(#versions:log(), 2, "no empty commits")

files["demo/playground/views/Window.etlua"] = nil
files["demo/playground/Model.lua"] = "return {}\n"
assert(save(files))
local second = assert(versions:record("Replace window"))
t.assertEqual(tracked(repo), ".gitignore,AppIcon.png,Model.lua,ProjectIcons/desk.png,ProjectIcons/rocket-sketch.png,ProjectIcons/rocket.png,init.lua,notes.txt,project.lua", "source deletion preserves metadata, project icons and unrelated files")
t.expect(io.open(workspace.root .. "/views/Window.etlua") == nil, "deleted files leave the worktree")
local history = versions:log()
t.assertEqual(#history, 3, "each change is one commit after inception")
t.assertEqual(history[1].id, second, "history is newest first")
t.assertEqual(history[1].author, "Lua Studio", "Studio authors its commits")
t.assertEqual(#versions:log(1), 1, "history can be limited")
versions:close()

local reopened = assert(Versions.open(Git, workspace.root))
t.assertEqual(reopened:log()[1].id, second, "reopening keeps the history")
t.assertEqual(reopened:record("Reopen"), false, "reopening adds no duplicate commit")
assert(workspace.localStorage.set("habits", '{"completed":false}'))
assert(write("HabitTracker/settings.json", '{"model":"another/model"}'))
t.assertEqual(reopened:record("Runtime data"), false, "habit and settings changes create no source commit")
t.assertEqual(read(workspace.root .. "/notes.txt"), "Keep my project notes", "unrelated files are preserved")
local savedIgnore = assert(read(workspace.root .. "/.gitignore")) .. "/scratch/\n"
assert(write("HabitTracker/.gitignore", savedIgnore))
local reopenedWorkspace = Workspace.open(documentNS, read, Git, "HabitTracker")
t.assertEqual(read(workspace.root .. "/.gitignore"), savedIgnore, "reopening preserves custom ignore rules")
t.expect(reopenedWorkspace.seed["demo/playground/views/Window.etlua"] == nil,
	"removed source stays removed after reopening")
local rejected, rejection = save({ ["demo/playground/.git/config"] = "bad" })
t.expect(not rejected and rejection:find("Invalid", 1, true), "project writes cannot overwrite Git metadata")
local metadata = assert(load(repo:show("HEAD", "project.lua"), "manifest", "t", {}))()
t.assertEqual(table.concat(metadata.files, ","), "Model.lua,init.lua", "committed manifest matches current source")
-- A failed stage is reported without attempting to commit.
local failing = setmetatable({ repo = { add = function() return nil, "locked" end } }, Versions)
local ok, err = failing:record("Fails")
t.expect(ok == nil and err == "locked", "staging failures are reported")
local blocked = root .. "/file"
assert(io.open(blocked, "w")):close()
ok, err = Versions.open(Git, blocked .. "/repo")
t.expect(ok == nil and type(err) == "string", "a repository that cannot be created is reported")
repo:close()
reopened:close()

-- Every creation path has the same repository contract, independent of the
-- starter name and before the project is published in the catalog.
local metadata = { name = "Notes", bundleId = "org.example.notes", appIcon = "note" }
local alpha = Workspace.create(documentNS, Git, "Notes", metadata, { ["init.lua"] = "return {}" })
local beta = Workspace.create(documentNS, Git, "Timer", {
	name = "Timer", bundleId = "org.example.timer", appIcon = "timer",
}, { ["init.lua"] = "return { timer = true }" })
t.assertEqual(alpha.versions.repo:workdir(), root .. "/Notes/", "created project owns its repository")
t.assertEqual(beta.versions.repo:workdir(), root .. "/Timer/", "another project owns a separate repository")
t.assertEqual(#alpha.versions:log(), 1, "new project has a commit before create returns")
t.assertEqual(#beta.versions:log(), 1, "each new project gets an initial commit")
t.assertEqual(alpha.versions.repo:show("HEAD", "init.lua"), "return {}", "initial commit includes initial source")
t.assertEqual(read(root .. "/Notes/AppIcon.png"), read("apps/studio/ProjectIcons/rocket-sketch.png"),
	"new projects receive the default rocket sketch icon")
t.expect(alpha.selectIcon("desk"), "projects can select another bundled icon")
t.assertEqual(read(root .. "/Notes/AppIcon.png"), read("apps/studio/ProjectIcons/desk.png"),
	"choosing an icon replaces the project's AppIcon.png")
local selectedMetadata = assert(load(assert(read(root .. "/Notes/project.lua")), "project", "t", {}))()
t.assertEqual(selectedMetadata.projectIcon, "desk", "the selected project icon choice persists in metadata")
local names = ns.json_parse(documentNS._documentRead("projects.json"))
t.assertEqual(table.concat(names, ","), "Notes,Timer", "successful projects enter the catalog")
local created = pcall(Workspace.create, documentNS, Git, "Notes", metadata, {})
t.expect(not created, "creating over an existing project is rejected")
t.expect(not pcall(Workspace.create, documentNS, Git, "../escape", metadata, {}), "creation rejects unsafe folder names")
local unavailable = { open = function() return nil, "missing" end, init = function() return nil, "disk full" end }
local ok, errorMessage = pcall(Workspace.create, documentNS, unavailable, "Failed", metadata, {})
t.expect(not ok and errorMessage:find("disk full", 1, true), "Git failure prevents successful project creation")
t.assertEqual(documentNS._documentRead("projects.json"), ns._jsonEncode(names), "failed creation is not published")
assert(alpha.storage.save({ files = { ["demo/playground/init.lua"] = "return { edited = true }" } }))
t.assertEqual(alpha.storage.load().files["demo/playground/init.lua"], "return { edited = true }",
	"created workspace reads saved edits instead of its original template")
local again = Workspace.open(documentNS, read, Git, "Notes")
t.assertEqual(#again.versions:log(), 1, "opening does not commit pending source edits")
t.assertEqual(again.seed["demo/playground/init.lua"], "return { edited = true }", "opening preserves pending source edits")
t.assertEqual(beta.versions.repo:show("HEAD", "init.lua"), "return { timer = true }", "another project's history is unchanged")
alpha.versions:close(); beta.versions:close(); again.versions:close()
workspace.versions:close(); reopenedWorkspace.versions:close()

-- The Commit action reports the result in the status line.
local Controller = require("apps.studio.Controller")
local recorded = {}
local controller = setmetatable({
	model = { files = files },
	versions = { record = function(_, message)
		table.insert(recorded, message)
		if message == "fail" then return nil, "locked" end
		if message == "same" then return false end
		return "0123456789abcdef0123456789abcdef01234567"
	end },
}, Controller)
t.expect(controller:commitProject("Update project"), "commit records the saved project")
t.assertEqual(recorded[1], "Update project", "the commit message is passed through")
t.assertEqual(controller.status, "Committed 0123456", "a commit shows its short id")
t.assertEqual(controller:commitProject("same"), false, "an unchanged project is not an error")
t.assertEqual(controller.status, "No changes to commit", "an unchanged project says so")
t.expect(controller:commitProject("fail") == nil, "a failed commit is reported")
t.assertEqual(controller.status, "Commit failed: locked", "the failure is shown")
controller.versions, controller.versionsError = nil, "no repository"
t.expect(controller:commitProject("x") == nil, "commit without a repository fails")
t.assertEqual(controller.status, "Git unavailable: no repository", "the open error is shown")

local source = require("ui.xml").describeFile("apps/studio/views/Workspace.etlua", {
	rail = require("apps.studio.models.Rail").presentation(),
	preview = require("apps.studio.models.Preview").presentation({}),
	chat = require("apps.studio.models.Chat").presentation(),
}).source
t.expect(source:find('title="Commit"[^>]*action="commitProject"') ~= nil, "the chat header's Commit button commits")

os.execute("/bin/rm -rf " .. root)
os.exit(t.summary() and 0 or 1)
