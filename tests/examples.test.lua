_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local examples = {
	"apps/diskmap/init.lua",
	"apps/studio/init.lua",
	"demo/playground/init.lua",
	"demo/hello/init.lua",
	"demo/controls/init.lua",
	"demo/list/init.lua",
	"demo/list-benchmark/init.lua",
	"demo/list-reorder/init.lua",
	"demo/container-reorder/init.lua",
	"demo/lazy-reorder/init.lua",
	"demo/swipe-actions/init.lua",
	"demo/glass-materials/init.lua",
	"demo/browser/init.lua",
	"demo/navigation-path/init.lua",
	"demo/motion-feedback/init.lua",
	"demo/mail/init.lua",
	"demo/layout/init.lua",
	"demo/welcome/init.lua",
	"demo/ide/init.lua",
	"apps/weather/init.lua",
	"apps/stocks/init.lua",
	"demo/snippets/init.lua",
	"apps/adventure-arena/init.lua",
	"demo/phone-tabs/init.lua",
	"demo/swiftui_parity/init.lua",
	"test/parity_batch/init.lua",
	"demo/zoom-cover/init.lua",
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
