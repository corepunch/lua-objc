_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local bridge = require("AppKitNative")
local Store = require("apps.diskmap.Store")
local Workflows = require("apps.diskmap.models.Workflows")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- Diskmap is for everyone (#52): the pages of a kind of work follow the
-- system pages, and appear only on a Mac that does that work.
local order = {}
for _, row in ipairs(Navigation.destinations) do if row.section then table.insert(order, row.title) end end
t.assertEqual(table.concat(order, ","), "Free Up Space,Explore,System,Everyday,Developer,Creative & Games,Learn", "work follows System")
-- #102: the cleanup entry points lead; browsing tools follow them.
t.assertEqual(Navigation.destinations[1].id, "overview", "Overview leads the sidebar")
t.assertEqual(Navigation.destinations[2].id, "cleanup", "Clean Up follows it, without a section to look for")
local sectionOf, current = {}, nil
for _, row in ipairs(Navigation.destinations) do
	if row.section then current = row.title elseif row.id then sectionOf[row.id] = current end
end
for _, id in ipairs({"applications", "files", "duplicates", "simulators", "worktrees", "projects"}) do
	t.assertEqual(sectionOf[id], "Free Up Space", id .. " is a cleanup destination")
end
for _, id in ipairs({"map", "folder", "largest", "kinds"}) do t.assertEqual(sectionOf[id], "Explore", id .. " is a browsing tool") end

local developer, music = Workflows:find("developer"), Workflows:find("music")
local model = Store.new("/Users/test")
t.expect(not developer:present(function() return false end), "a Mac without developer folders has no Developer section")
t.expect(developer:present(function(path) return path == "/Users/test/Library/Developer" end), "~/Library/Developer shows it")
t.expect(developer:present(function(path) return path == "/Applications/Xcode.app" end), "Xcode shows it")
t.expect(not music:present(function(path) return path == "/Applications/Xcode.app" end), "Xcode does not make a musician")
t.expect(music:present(function(path) return path == "/Applications/Logic Pro.app" end), "Logic Pro shows Music Production")
model.measurements.derived = {status = "complete", bytes = 900e6}
t.expect(developer:present(nil), "measured developer data shows it")
t.expect(not music:present(nil), "and no other kind of work")
model.measurements["fonts-shared"] = {status = "complete", bytes = 900e6}
t.expect(not Workflows:find("design"):present(nil), "the fonts every Mac has do not make a designer")

-- Every workflow cites catalog groups and locations that exist, and has
-- what its page and sidebar row need.
local ids = {}
for _, workflow in ipairs(Workflows:all()) do
	t.expect(not ids[workflow.id], "workflow ids are unique: " .. workflow.id); ids[workflow.id] = true
	for _, key in ipairs({"noun", "summary", "empty", "footnote"}) do
		t.expect(type(workflow[key]) == "string" and workflow[key] ~= "", workflow.id .. " has " .. key)
	end
	-- Its sidebar row, header, icon and color belong to its page in app.xml.
	local row = require("apps.diskmap.controllers.NavigationController").page(workflow.id)
	for _, key in ipairs({"name", "icon", "color"}) do
		t.expect(row and type(row[key]) == "string" and row[key] ~= "", workflow.id .. " has " .. key .. " in app.xml")
	end
	t.assertEqual(row and row.workflow, workflow.id, workflow.id .. " is gated on its own work")
	t.expect(#workflow.sections > 0, workflow.id .. " has sections")
	for _, section in ipairs(workflow.sections) do
		for _, id in ipairs(section.groups or {}) do
			local group = Locations:find(id)
			t.expect(group ~= nil and not group:isLeaf(), workflow.id .. " cites a catalog group: " .. id)
		end
		for _, id in ipairs(section.roots or {}) do t.expect(Locations:find(id) ~= nil, workflow.id .. " cites a catalog root: " .. id) end
		for _, id in ipairs(section.items or {}) do
			local item = Locations:find(id)
			t.expect(item ~= nil and item:isLeaf(), workflow.id .. " cites a catalog location: " .. id)
		end
	end
	for _, link in ipairs(workflow.links or {}) do
		t.expect(link.page ~= nil or Locations:find(link.open) ~= nil, workflow.id .. " links to a resource or a page: " .. tostring(link.open or link.page))
	end
end

-- A page lists its measured locations, largest first, and totals them.
model.measurements["logic-sound-library"] = {status = "complete", bytes = 60e9}
model.measurements.ableton = {status = "complete", bytes = 20e9}
model.measurements["audio-plugins-shared"] = {status = "complete", bytes = 4e9}
local page = music:presentation()
t.assertEqual(#page.sections, 3, "sections with measured locations are shown")
t.assertEqual(page.sections[1].rows[1].id, "logic-sound-library", "rows name catalog locations")
t.assertEqual(page.total, "84.0 GB", "the page totals what it shows")
t.assertEqual(page.sections[1].rows[1].relative, 1, "the largest row has a full bar")
t.assertEqual(music:badge(), "84.0 GB", "the sidebar badge is the page's total")
-- A location can matter to two kinds of work.
model.measurements["adobe-caches"] = {status = "complete", bytes = 3e9}
local function lists(workflow, id)
	for _, section in ipairs(Workflows:find(workflow):presentation().sections) do
		for _, row in ipairs(section.rows) do if row.id == id then return true end end
	end
	return false
end
t.expect(lists("video", "adobe-caches") and lists("design", "adobe-caches"), "Adobe caches are on the video and the design page")

local shown
local navigation = Navigation.new(function(id) shown = id end)
local plain = #navigation:list()
for _, row in ipairs(navigation:list()) do t.expect(not row.workflow and row.title ~= "Developer", "no kind of work is listed before it is known") end
t.expect(navigation:setWorkflows({developer = true}), "the Developer section can be shown")
t.assertEqual(#navigation:list(), plain + 6, "showing adds the header and its five pages")
t.expect(not navigation:setWorkflows({developer = true}), "showing twice changes nothing")
t.expect(navigation:setWorkflows({developer = true, music = true, games = true}), "other work is shown beside it")
t.assertEqual(#navigation:list(), plain + 6 + 3, "one header for both pages")
t.expect(navigation:setWorkflows({}), "and hidden again")
t.assertEqual(#navigation:list(), plain, "nothing else changed")

-- The app hides them on a Mac without that data.
local Controller = require("apps.diskmap.Controller")
local service = require("apps.diskmap.services.Contract").stub({monitor = function() end, start = function() return {} end, await = function() end, cancel = function() end,
	diskSpace = function() return {totalKb = 10000, freeKb = 5000} end, exists = function() return false end})
local app = Controller.new(service)
app:createWindow()
local sidebar = app.navigation.refs.sidebar
t.assertEqual(sidebar.rowCount, plain, "an ordinary Mac's sidebar has no Developer or creative pages")
app.env.model.measurements.derived = {status = "complete", bytes = 900e6}
app:updateRows()
t.assertEqual(sidebar.rowCount, plain + 6, "the section appears once developer data is measured")
t.assertEqual(bridge._tableCell(sidebar, 0, app.navigation:index("developer") - 1).textField.stringValue, "Developer", "under its own header")
app.env.model.measurements["steam-games"] = {status = "complete", bytes = 40e9}
app:updateRows()
t.assertEqual(sidebar.rowCount, plain + 8, "Games appears once games are measured")
-- A rescan clears sizes; the pages stay.
app.env.model.measurements.derived = {status = "calculating"}
app.env.model.measurements["steam-games"] = {status = "calculating"}
app:updateRows()
t.assertEqual(sidebar.rowCount, plain + 8, "pages stay while a rescan measures again")
app:show("games")
t.expect(app.page.refs.list_installed ~= nil or app.page.refs.workflowEmpty ~= nil, "the Games page mounts")

os.exit(t.summary() and 0 or 1)
