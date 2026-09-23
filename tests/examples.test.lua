_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local examples = {
	"apps/diskmap/init.lua",
	"apps/studio/init.lua",
	"apps/playground/init.lua",
	"apps/hello/init.lua",
	"apps/controls/init.lua",
	"apps/list/init.lua",
	"apps/list-reorder/init.lua",
	"apps/mail/init.lua",
	"apps/layout/init.lua",
	"apps/welcome/init.lua",
	"apps/ide/init.lua",
	"apps/weather/init.lua",
	"apps/stocks/init.lua",
	"apps/snippets/init.lua",
	"apps/adventure-arena/init.lua",
	"apps/phone-tabs/init.lua",
	"apps/swiftui_parity/init.lua",
	"apps/parity_batch/init.lua",
	"apps/zoom-cover/init.lua",
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
