_G.__headless = true

local App = require("App")
local Source = require("examples.ide.plugins.source")
local Recent = require("examples.ide.state.recent")
local t = require("TestKit")

local files = {
	"examples/ide/main.lua",
	"examples/ide/app.lua",
	"examples/ide/state/recent.lua",
	"examples/ide/components/recent.lua",
	"examples/ide/components/welcome.lua",
	"examples/ide/plugins/source.lua",
	"lua/Plugins/ImageViewer.lua",
	"examples/ide/workspace.lua",
	"examples/ide/welcome.lua",
}

for _, path in ipairs(files) do
	local ok, err = pcall(function()
		local fn, loadErr = loadfile(path)
		if not fn then error(loadErr) end
		return fn()
	end)
	t.expect(ok, path .. " loads headlessly")
	if not ok then
		io.stderr:write("  " .. tostring(err) .. "\n")
	end
end

local tempRoot = "/private/tmp/lua-objc-ide-headless"
local recent = Recent.new {
	key = "headless-route-test",
	storageRoot = tempRoot,
	limit = 4,
}
recent:clear()

local calls = {}
local app = App.new {
	recent = recent,
	openFolder = function(self, folder)
		calls[#calls + 1] = { kind = "folder", path = folder }
		return { kind = "folder", path = folder }
	end,
	openFile = function(self, path)
		calls[#calls + 1] = { kind = "file", path = path }
		return { kind = "file", path = path }
	end,
	welcome = function(self)
		calls[#calls + 1] = { kind = "welcome" }
		return { kind = "welcome" }
	end,
}

local originalArg = _G.arg

_G.arg = {}
local welcomeView = app:run()
t.assertEqual(welcomeView.kind, "welcome", "App:run shows welcome without a folder argument")
t.assertEqual(calls[#calls].kind, "welcome", "welcome callback is used when no folder is passed")

_G.arg = { "/private/tmp/project-a" }
local workspaceView = app:run()
t.assertEqual(workspaceView.kind, "folder", "App:run opens a folder when one is passed")
t.assertEqual(calls[#calls].path, "/private/tmp/project-a", "folder argument is forwarded to openFolder")

_G.arg = originalArg

app:openFolder("/private/tmp/project-b")
app:openFile("/private/tmp/project-b/main.lua")

local imageWindow = Source.openFile("tests/fixtures/oversized.svg", app)
t.expect(imageWindow ~= nil, "image source route creates a window")
t.assertEqual(imageWindow.title, "oversized.svg", "image source route uses the file name as title")

t.assertEqual(#recent:folders(), 2, "recent folders are stored separately")
t.assertEqual(#recent:files(), 2, "recent files are stored separately")
t.assertEqual(recent:folders()[1].path, "/private/tmp/project-b", "most recent folder is first")
t.assertEqual(recent:files()[1].path, "tests/fixtures/oversized.svg", "most recent file is first")
t.assertEqual(recent:files()[2].path, "/private/tmp/project-b/main.lua", "older file remains available")

recent:clear()

os.exit(t.summary() and 0 or 1)
