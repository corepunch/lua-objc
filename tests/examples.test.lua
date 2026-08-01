_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local examples = {
	"examples/hello/init.lua",
	"examples/list/init.lua",
	"examples/mail/init.lua",
	"examples/layout/init.lua",
	"examples/welcome/init.lua",
	"examples/ide/init.lua",
	"examples/IDEKit/init.lua",
	"examples/IDEKit/App.lua",
	"examples/IDEKit/state/Recent.lua",
	"examples/IDEKit/Recent.lua",
	"examples/IDEKit/Welcome.lua",
	"examples/IDEKit/Workspace.lua",
	"examples/IDEKit/plugins/TextEditor.lua",
	"examples/IDEKit/plugins/ImageViewer.lua",
	"examples/IDEKit/plugins/NativeControls.lua",
}

for _, path in ipairs(examples) do
	local ok, err = pcall(function()
		local fn, loadErr = loadfile(path)
		if not fn then error(loadErr) end
		fn()
	end)
	t.expect(ok, path .. " loads without error")
	if not ok then
		io.stderr:write("  " .. tostring(err) .. "\n")
	end
end

os.exit(t.summary() and 0 or 1)
