_G.__headless = true
local t = require("TestKit")

for _, name in ipairs({"iPad-01-workspace", "iPad-02-dark", "iPad-03-agent", "iPad-04-github"}) do
	local file = assert(io.open("apps/studio/store-assets/screenshots/en-US/" .. name .. ".png", "rb"))
	local header = file:read(24)
	file:close()
	t.assertEqual(header:sub(1, 8), "\137PNG\r\n\26\n", name .. " is a PNG")
	local width, height = string.unpack(">I4I4", header, 17)
	t.assertEqual(width, 2752, name .. " retains native iPad landscape width")
	t.assertEqual(height, 2064, name .. " retains native iPad landscape height")
end

os.exit(t.summary() and 0 or 1)
