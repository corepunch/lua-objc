_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local Categories = require("apps.diskmap.models.Categories")
local model = Model.new("/Users/test")
local function set(values) local result = {}; for _, value in ipairs(values) do result[value] = true end; return result end
local paths, ids, exclusions = Inventory.plan(model)
local roots, blocked = set(paths), set(exclusions)
for _, id in ipairs({"pictures", "music", "movies"}) do
	local path = model.resources:find(id).path
	t.expect(not roots[path], "default scan never opens " .. id)
	t.expect(blocked[path], "parent residual cannot enter " .. id)
	t.assertEqual(model.measurements[id].status, "excluded", "excluded library is visibly unknown")
	t.assertEqual(model.measurements[id].bytes, nil, "skipped library is never counted as empty")
end
t.expect(blocked["/Users/test/Library/Containers/com.apple.Photos"], "Photos container is not reached by app residual")
t.expect(blocked["/Users/test/Library/Containers/com.apple.Music"], "Music container is not reached by app residual")
local sections = {}
for _, row in ipairs(Categories.rows(model)) do sections[row.name] = row end
for _, name in ipairs({"Applications", "Trash", "Books", "Developer", "Documents", "iCloud Drive", "iOS Files", "Mail", "Messages", "Music", "Music Creation", "Photos", "Podcasts", "TV", "Other Users & Shared", "macOS", "System Data", "AI agents", "Backups"}) do
	t.expect(sections[name] ~= nil, "storage list includes " .. name)
end
t.assertEqual(sections.Photos.size, "Not scanned", "Photos communicates the media opt-in")
t.assertEqual(sections.Music.size, "Not scanned", "Music communicates the media opt-in")
t.assertEqual(sections.TV.size, "Not scanned", "TV communicates the media opt-in")
model.includeMedia = true
paths, ids = Inventory.plan(model); roots = set(paths)
for _, id in ipairs({"pictures", "music", "movies"}) do t.expect(roots[model.resources:find(id).path], "session opt-in includes " .. id) end
Inventory.begin(model, ids)
t.assertEqual(model.measurements.music.status, "calculating", "opt-in starts a fresh measurement")
model.measurements.music = {bytes = 12345, status = "complete"}
model.includeMedia = false; Inventory.plan(model)
t.assertEqual(model.measurements.music.bytes, nil, "opting out removes stale library sizes")
t.expect(not Model.new("/Users/test").includeMedia, "new launch always defaults to excluding libraries")
os.exit(t.summary() and 0 or 1)
