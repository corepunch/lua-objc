_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local System = require("apps.diskmap.services.System")
local Catalog = require("apps.diskmap.Catalog")

-- Inside the App Sandbox HOME names Diskmap's container, so the service
-- takes the home folder from the user database instead.
local home = ns.homeDirectory()
t.expect(type(home) == "string" and home:sub(1, 1) == "/", "the home folder comes from the user database")
t.assertEqual(System.home, home, "the service measures the person's home folder")
t.expect(not System.home:find("/Library/Containers/", 1, true), "never an app container")

-- Outside the sandbox nothing hides the disk.
if not System.sandboxed() then
	t.expect(System.hasDiskAccess(), "an unsandboxed run needs no disk grant")
end

-- Features macOS manages from Settings say what to do on every row, so a
-- size alone does not leave the person guessing (TestFlight feedback).
local function find(rows, id)
	for _, row in ipairs(rows) do
		if row.id == id then return row end
		local found = row.children and find(row.children, id)
		if found then return found end
	end
end
local tree = Catalog.tree("/Users/test")
for _, id in ipairs({"siri-assets", "foundation-models", "dictation", "voices"}) do
	local group = find(tree, id)
	t.expect(group ~= nil, id .. " is in the catalog")
	t.expect(group.subtitle:find("Turn it off", 1, true) or group.subtitle:find("Remove voices", 1, true), id .. " says what to do")
	for _, child in ipairs(group.children) do
		t.assertEqual(child.subtitle, group.subtitle, id .. " classes repeat the advice")
		t.expect(child.action == "settings" and child.settingsSection ~= nil, id .. " classes open their Settings pane")
	end
end
t.expect(find(tree, "siri-assets").subtitle:find("may then remove", 1, true), "turning Siri off promises no reclaim")

os.exit(t.summary() and 0 or 1)
