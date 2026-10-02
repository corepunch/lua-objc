-- Diskmap's page set, sidebar and Go menu come from one file, app.xml.
_G.__headless = true
local t = require("TestKit")
local Manifest = require("data.manifest")
local App = require("data.app")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local Workflows = require("apps.diskmap.knowledge.Workflows")

local manifest = Manifest.load("apps/diskmap/app.xml")
t.assertEqual(App.launcher("apps/diskmap/app.xml"), Controller, "the manifest's root controller is the launch class")
t.assertEqual(manifest.startup, "overview", "the startup page")

-- Every page of the file is built, and nothing else is.
local app = Controller.new(Mock.new())
local expected = 0
for _, entry in ipairs(manifest.order) do
	expected = expected + 1
	t.expect(app.pages[entry.id] ~= nil, entry.id .. " has a page controller")
end
local built = 0
for _ in pairs(app.pages) do built = built + 1 end
t.assertEqual(built, expected, "the page table holds exactly the manifest's pages")

-- The sidebar rows are the manifest's, in order, with headers for sections.
local rows, index = {}, 0
for _, section in ipairs(manifest.sections) do
	if section.title then table.insert(rows, "section:" .. section.title) end
	for _, page in ipairs(section.pages) do table.insert(rows, page.id) end
end
for _, row in ipairs(Navigation.destinations) do
	index = index + 1
	t.assertEqual(row.section and ("section:" .. row.title) or row.id, rows[index], "sidebar row " .. index .. " follows app.xml")
end
t.assertEqual(index, #rows, "and there are no others")
t.expect(Navigation.page("watched") == nil, "an unlisted page has no sidebar row")

-- The Go menu lists the same pages.
local data = app.commands:data()
local listed = {}
for _, section in ipairs(data.sections) do for _, page in ipairs(section.pages) do listed[page.id] = true end end
for _, entry in ipairs(manifest.order) do
	t.assertEqual(listed[entry.id] == true, entry.listed, entry.id .. (entry.listed and " is" or " is not") .. " in the Go menu")
end

-- Workflow pages are gated on their own work, and each names its workflow.
for _, workflow in ipairs(Workflows.list) do
	t.assertEqual(manifest.pages[workflow.id].attrs.workflow, workflow.id, workflow.id .. " page is gated on its workflow")
end
os.exit(t.summary() and 0 or 1)
