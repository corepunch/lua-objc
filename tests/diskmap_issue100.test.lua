local t = require("TestKit")
local Recommendations = require("apps.diskmap.models.Recommendations")

-- Clean Up leads with actions: no summary tiles, files and apps before the
-- review inventory, and the checked inventory collapsed.
local page = Recommendations.page(function() return nil end)
t.expect(page.layout.tiles == nil, "Clean Up has no summary tiles ahead of its lists")
local order = {}
for _, section in ipairs(page.layout.sections) do table.insert(order, section.id) end
t.assertEqual(table.concat(order, ","), "section_rebuildable,section_elsewhere,section_review,section_checked",
	"rebuildable, files and apps, then review, then the checked inventory")
t.expect(page.layout.sections[4].collapsed, "the checked inventory is collapsed by default")
t.assertEqual(Recommendations.details(nil, nil).detail, "", "an empty inspector stays compact")
os.exit(t.summary() and 0 or 1)
