_G.__headless = true
local t = require("TestKit")
local fixtures = require("tests.support.diskmap_fixtures").new()
for _, name in ipairs({"hero", "notMeasured", "decision", "kinds", "changes", "tips", "settings"}) do
	local view, refs = fixtures:render(name)
	t.expect(view ~= nil and refs ~= nil, name .. " renders with its real presentation data and bound actions")
end
local settings = fixtures:get("settings")
t.assertEqual(settings.request.switches.media, fixtures.host.env.model.includeMedia, "Settings preview uses the loaded preference")
local changes = fixtures:get("changes")
t.expect(#changes.data.lists.changes > 0, "Changes preview uses measured location deltas")
t.assertThrows(function() fixtures:get("missing") end, "unknown preview fails explicitly")
fixtures:dispose()
os.exit(t.summary() and 0 or 1)
