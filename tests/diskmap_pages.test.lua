_G.__headless = true
local t = require("TestKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local bridge = require("AppKitNative")

-- Every sidebar page against the synthetic Mock HDD, end to end: mark from
-- each page, review, move to Trash, empty it, and read the history.
local service = Mock.new()
local confirmations = {}
service.confirmAction = function(title) table.insert(confirmations, title); return true end
local shownErrors = {}
service.showError = function(title) table.insert(shownErrors, title) end
local ns = require("AppKit")
local app = Controller.new(service)
local window = app:createWindow()
local function page() return app.page.refs end
-- Performs the row menu item titled `title` on a list row (1-based).
local function perform(list, row, title)
	for index, item in ipairs(bridge._tableRowMenu(list, row)) do
		if item.title == title then bridge._tableRowMenu(list, row, index); return true end
	end
	return false
end

t.expect(window.subtitle:find("available of", 1, true) ~= nil and not window.subtitle:find("free", 1, true),
	"the window subtitle is Finder's one number, purgeable storage included, short enough for the toolbar")
t.expect(app.pages.overview.hero.refs.hiddenSpace ~= nil, "the overview lists hidden space")

-- Map: rings by default, drill in and out, switch to rectangles.
app:show("map")
t.expect(page().sunburst ~= nil and page().sunburst.subviews[1].className == "LuaArcView",
	"the map starts as flat rings")
t.expect(page().sunburst.subviews[1].fitDiameter > 0, "which scale to their pane")
t.expect(page().mapList.rowCount > 5, "the map lists the focus's children")
-- The rings scale to their pane instead of scrolling inside it, and "Worth a
-- look" sits under the list so the rings keep the pane's height.
local function inside(view, ancestor)
	while view do
		if view == ancestor then return true end
		view = view.superview
	end
	return false
end
local function scrolled(view, stop)
	while view and view ~= stop do
		if view.className == "NSScrollView" then return true end
		view = view.superview
	end
	return false
end
t.expect(inside(page().sunburst, page().mapChartPane) and not scrolled(page().sunburst, page().mapChartPane),
	"the rings sit in their pane with no scroll view of their own")
t.expect(page().worthMark_1 ~= nil and not inside(page().worthMark_1, page().mapChartPane),
	"beside the rings, Worth a look sits under the list")
-- Slivers fold into "Other" so every mark is wide enough to see and point at.
local MapTree = require("apps.diskmap.models.MapTree")
local mapNodes, mapTotal = MapTree.nodes(app.model, "")
for _, node in ipairs(mapNodes) do
	t.expect(node.value / mapTotal >= MapTree.minimumShare or (node.other and node.ring == 1),
		"map node " .. node.id .. " is not a sliver")
end
local mapById, childCount = {}, {}
for _, node in ipairs(mapNodes) do
	mapById[node.id] = node
	if node.parent then childCount[node.parent] = (childCount[node.parent] or 0) + 1 end
end
for _, node in ipairs(mapNodes) do
	if node.other and node.parent then
		t.expect(childCount[node.parent] > 1, node.id .. " is never its parent's only child")
		t.assertEqual(node.color, mapById[node.parent].color, node.id .. " keeps its parent's hue")
	end
end
app.page.template.actions.chartSelect("developer", 1)
t.assertEqual(app.pages.map.focus, "developer", "clicking a group focuses it")
t.assertEqual(page().mapFocus.text, "Developer", "the breadcrumb ends at the focus")
app.page.template.actions.style(1)
t.expect(page().treemap ~= nil and page().sunburst == nil, "rectangles replace the rings")
t.assertEqual(page().mapList, nil, "rectangles name every item, so the list serves the rings only")
local treemapWidth = page().mapChartPane.frame.size.width
t.expect(inside(page().worthMark_1, page().mapChartPane), "without a list, Worth a look sits under the rectangles")
app.page.template.actions.chartHover("xcode")
t.expect(page().mapHover.text:find("Developer › Xcode", 1, true) == 1, "hover describes a node in place")
app.page.template.actions.up()
t.assertEqual(app.pages.map.focus, "", "the center or breadcrumb goes back up")
app.page.template.actions.style(0)
t.expect(page().mapList ~= nil and page().mapList.rowCount > 0, "the rings bring the list back")
t.expect(page().mapChartPane.frame.size.width < treemapWidth, "the rectangles take the list's width")

-- Applications: leftovers carry a confidence tier; High can be marked at once.
app:show("applications")
local leftovers = page().leftovers
t.expect(leftovers.rowCount >= 4, "leftovers list unclaimed folders")
t.assertEqual(bridge._tableCell(leftovers, 1, 0).textField.stringValue, "High", "the most certain leftovers come first")
-- #102: the page leads with the leftover decision and its bulk action,
-- above the installed-app inventory.
local lead = app.page.leadRefs
t.expect(lead.decisionTitle.stringValue:find("leftover folder", 1, true) ~= nil, "the page leads with the leftover review")
t.assertEqual(lead.decisionCaption.stringValue, "could recover", "high-confidence leftovers state what they could recover")
t.expect(lead.decisionAction.enabled, "high-confidence leftovers can be marked together")
local order = {}
for index, view in ipairs(page().pageContent.subviews) do order[view] = index end
local installed = page().apps
while installed and not order[installed] do installed = installed.superview end
t.expect(order[page().lead] < order[page().leftoversSection] and order[page().leftoversSection] < order[installed],
	"the decision comes before the leftovers, and the leftovers before the installed apps")
app.page.template.actions.markHigh()
local marked = app.review:count()
t.expect(marked >= 2, "every high-confidence leftover is marked")
t.assertEqual(app.page.leadRefs.decisionAction.title, "Review Marked Items…", "fully staged leftovers offer final review")
t.expect(app.page.leadRefs.decisionAction.enabled, "review stays accessible after staging")
t.expect(perform(leftovers, 1, "Unmark"), "a marked row offers Unmark in its menu")
t.assertEqual(app.review:count(), marked - 1, "unmarking removes the row from the basket")
t.expect(perform(leftovers, 1, "Mark for Cleanup"), "a row is marked from its menu")
t.assertEqual(app.review:count(), marked, "marking adds the row again")

-- Xcode: older device support and missing projects.
app:show("xcode")
t.assertEqual(page().list_support.rowCount, 4, "device support lists each OS version")
t.assertEqual(page().list_derived.rowCount, 2, "DerivedData lists each project")
t.assertEqual(page().list_archives.rowCount, 2, "archives are listed")
t.expect(page().bulk_support.enabled and page().bulk_derived.enabled, "bulk marks start enabled")
app.page.template.actions.bulk_support()
app.page.template.actions.bulk_derived()
t.assertEqual(app.review:count(), marked + 3, "older device support and missing projects are marked")
t.expect(not page().bulk_support.enabled, "marked sections disable their bulk action")
t.assertEqual(bridge._tableRowMenu(page().list_support, 2)[1].title, "Unmark", "marked rows say so in their menu")

-- Projects: artifacts grouped with git state.
app:show("projects")
t.assertEqual(page().projects.rowCount, 2, "artifacts group into their project")
t.expect(page().projectsSummary.text:find("2 projects", 1, true) ~= nil, "the summary counts projects")
t.assertEqual(bridge._tableRowMenu(page().projects, 1)[1].title, "Mark Build Data for Cleanup", "a project marks its build data")

-- Updates: installers found in Downloads.
app:show("updates")
t.expect(page().installers ~= nil and page().installers.rowCount >= 1, "installers found on disk are listed")
t.expect(perform(page().installers, 1, "Mark for Cleanup"), "an installer can be marked")
local total = app.review:count()
t.assertEqual(total, marked + 4, "the installer joins the basket")
t.expect(window.subtitle:find(total .. " marked for cleanup", 1, true) ~= nil, "the subtitle counts marked items")

-- The collector marks what is dropped on it.
local before = app.review:count()
local dropPath = app.model.home .. "/Downloads/Dropped Installer.dmg"
t.expect(bridge._dropFiles(app.collector.collector, {dropPath}), "a file dropped on the collector is marked")
t.assertEqual(app.review:count(), before + 1, "the dropped file joins the basket")
t.expect(app.collector.collectorText.text:find((before + 1) .. " items", 1, true) ~= nil and app.collector.collectorReview.enabled,
	"the collector counts marked items and offers Review")
t.expect(not bridge._dropFiles(app.collector.collector, {"/System"}), "system locations are refused")
t.assertEqual(shownErrors[#shownErrors], "Some items were not marked", "a refusal is explained")
app.review:toggle({path = dropPath})
total = app.review:count()

-- Review: move to Trash, empty, and measure what was freed.
app:openReview()
t.assertEqual(app.review.refs.items.rowCount, total, "the review lists every marked item")
local before = service.diskSpace().freeKb
t.expect(app.review:trash(), "marked items move to the Trash after confirmation")
t.assertEqual(app.review:count(), 0, "moved items leave the basket")
t.assertEqual(service.diskSpace().freeKb, before, "moving to Trash frees nothing yet")
t.expect(not app.review.refs.emptyTrash.hidden, "emptying the Trash is offered next")
t.expect(app.review:emptyTrash(), "the Trash can be emptied")
t.expect(service.diskSpace().freeKb > before, "emptying the Trash frees space")
t.expect(app.review.refs.reviewSummary.text:find("more free space", 1, true) ~= nil, "freed space is reported as measured")
app.review:close()
app.history:open(window)
t.assertEqual(app.history.refs.entries.rowCount, total + 1, "every move and the empty are in the history")
app.history:close()

-- Back and forward follow visited pages.
t.expect(app.navigation:back(), "back is available after navigating")
t.assertEqual(app.destination, "projects", "back returns to the previous page")
t.expect(app.navigation:forward(), "forward is available after going back")
t.assertEqual(app.destination, "updates", "forward returns again")
t.expect(bridge._navigationGesture(window, "back") and app.destination == "projects", "the mouse's back button goes back")
t.expect(bridge._navigationGesture(window, "forward") and app.destination == "updates", "the mouse's forward button goes forward")

-- The Overview's ring is interactive: a sector names itself in the center
-- while hovered and opens the Map inside its category; the center opens the
-- whole map.
app.pages.map:setFocus("")
app:show("overview")
local hero = app.pages.overview.hero
local heroActions = hero.actions
local usedTotal, usedCaption = hero.refs.usedTotal.text, hero.refs.usedCaption.text
t.assertEqual(hero.refs.chart.subviews[#hero.refs.chart.subviews].className, "LuaPointerView", "the overview ring takes the pointer")
heroActions.chartHover("developer")
t.expect(hero.refs.chartDetail.text:find("Developer · ", 1, true) == 1, "a hovered sector names itself under the ring")
t.expect(hero.refs.chartDetail.text:find("%d+%%$") ~= nil, "with its size and share")
t.assertEqual(hero.refs.usedTotal.text, usedTotal, "the center keeps the used total")
t.assertEqual(hero.refs.usedCaption.text, usedCaption, "and its caption")
heroActions.chartHover(nil)
t.assertEqual(hero.refs.chartDetail.text, "", "leaving it clears the line")
heroActions.chartSelect("free")
t.assertEqual(app.destination, "overview", "free space has nothing inside to open")
heroActions.chartSelect("developer")
t.assertEqual(app.destination, "map", "clicking a category's sector opens the Map")
t.assertEqual(app.pages.map.focus, "developer", "inside that category")
app:show("overview")
app.pages.overview.hero.actions.chartCenter()
t.assertEqual(app.destination, "map", "the center opens the Map")
t.assertEqual(app.pages.map.focus, "", "at the whole disk")

-- The keyboard does the same: focus names a sector, Return opens it, and
-- Delete, which has no level to go up to here, stays on the page.
app:show("overview")
hero = app.pages.overview.hero
local heroPointer = hero.refs.chart.subviews[#hero.refs.chart.subviews]
t.expect(heroPointer.acceptsFirstResponder, "the overview ring takes keyboard focus")
bridge._pointerSend(heroPointer, "key", "tab")
t.expect(hero.refs.chartDetail.text ~= "", "a focused sector names itself under the ring")
t.assertEqual(hero.refs.usedCaption.text, usedCaption, "the center keeps its caption")
bridge._pointerSend(heroPointer, "key", "delete")
t.assertEqual(app.destination, "overview", "delete stays on the overview")
-- Tab starts at the largest sector, space no category accounts for.
t.expect(hero.refs.chartDetail.text:find("Not attributed · ", 1, true) == 1, "tab focuses the largest sector")
bridge._pointerSend(heroPointer, "key", "return")
t.assertEqual(app.destination, "overview", "which has nothing inside to open")
for _ = 1, 8 do
	if hero.refs.chartDetail.text:find("Developer · ", 1, true) == 1 then break end
	bridge._pointerSend(heroPointer, "key", "right")
end
t.expect(hero.refs.chartDetail.text:find("Developer · ", 1, true) == 1, "arrows reach the categories")
bridge._pointerSend(heroPointer, "key", "return")
t.assertEqual(app.destination, "map", "return opens the Map inside the focused category")
t.assertEqual(app.pages.map.focus, "developer", "focused on it")
app.pages.map:setFocus("")

-- Drilling takes the new level in place.
local rings = app.page.refs.sunburst
app.page.template.actions.chartSelect("developer", 1)
t.expect(app.page.refs.sunburst == rings, "drilling keeps the chart view")
app.page.template.actions.up()
t.expect(app.page.refs.sunburst == rings, "and so does going back out")
require("AppKitNative")._motionSettle()


os.exit(t.summary() and 0 or 1)
