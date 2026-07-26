_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local examples = {
	"examples/hello.lua",
	"examples/list.lua",
	"examples/mail.lua",
	"examples/layout.lua",
	"examples/welcome.lua",
	"examples/ide.lua",
	"examples/ide/main.lua",
	"examples/ide/app.lua",
	"examples/ide/state/recent.lua",
	"examples/ide/components/recent.lua",
	"examples/ide/components/welcome.lua",
	"examples/ide/plugins/source.lua",
	"examples/ide/plugins/text_editor.lua",
	"examples/ide/plugins/image_viewer.lua",
	"examples/ide/plugins/native_controls.lua",
	"examples/ide/workspace.lua",
	"examples/ide/welcome.lua",
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
