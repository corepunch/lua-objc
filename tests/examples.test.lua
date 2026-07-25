_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local examples = {
	"examples/hello.lua",
	"examples/list.lua",
	"examples/mail.lua",
	"examples/layout.lua",
	"examples/welcome.lua",
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
