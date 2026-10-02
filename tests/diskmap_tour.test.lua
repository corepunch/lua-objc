_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Tour = require("apps.diskmap.helpers.Tour")

-- A JPEG's pixel size, from its start-of-frame segment.
local function jpegSize(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local data = file:read("a"); file:close()
	local at = 3
	while at < #data do
		local marker, length = data:byte(at + 1), data:byte(at + 2) * 256 + data:byte(at + 3)
		if marker >= 0xC0 and marker <= 0xC2 then
			return data:byte(at + 7) * 256 + data:byte(at + 8), data:byte(at + 5) * 256 + data:byte(at + 6)
		end
		at = at + 2 + length
	end
end

-- Every screenshot fills the tour's image box exactly, at twice its size,
-- in light and dark (tour/capture.lua crops them so).
local BOX = { width = 524, height = 290, scale = 2 }
local template = io.open("apps/diskmap/views/sheets/Tour.etlua"):read("a")
t.expect(template:find("imageWidth = " .. BOX.width .. ", imageHeight = " .. BOX.height, 1, true) ~= nil, "the view's image box matches the captures")
local plan = io.open("apps/diskmap/tour/capture.lua"):read("a")
t.expect(plan:find("local BOX = { width = " .. BOX.width .. ", height = " .. BOX.height .. ", scale = " .. BOX.scale .. " }", 1, true) ~= nil, "and so does the capture plan")
t.expect(#Tour.pages >= 8 and #Tour.pages <= 10, "a short tour: eight to ten pages")
for _, page in ipairs(Tour.pages) do
	t.expect(plan:find('name = "' .. page.id .. '"', 1, true) ~= nil, page.id .. " has a shot in the capture plan")
	for _, path in ipairs({page.image, page.darkImage}) do
		local width, height = jpegSize(path)
		t.expect(path:match("%.jpg$") ~= nil and width ~= nil, path .. " is a committed JPEG")
		t.expect(width == BOX.width * BOX.scale and height == BOX.height * BOX.scale, path .. " is exactly twice the box")
	end
	t.expect(#page.title > 0 and #page.text > 0, page.id .. " explains its screenshot")
end

-- Image darkPath: one view whose bitmap follows the appearance.
local image = xml.render('<Image path="' .. Tour.pages[1].image .. '" darkPath="' .. Tour.pages[1].darkImage .. '" width="262" height="145" />', {}, ns)
t.expect(image ~= nil, "an Image with a dark variant renders")

-- Pages change at once; the system's push transition does the sliding.

-- On start on a real Mac, while the scan runs.
local service = Mock.new()
service.hasFullDiskAccess = function() return true end
local app = Controller.new(service)
app:createWindow()
local tour = app.tour
t.expect(tour.sheet ~= nil, "the tour opens on start")
t.expect(app.model.scan.completedAt ~= nil, "the scan does not wait for the tour")
t.expect(tour.refs.showOnStart.state == 1, "Show this window on start is on for a new install")
t.expect(not tour.refs.page_1.hidden and tour.refs.page_2.hidden, "page one shows first")
t.expect(tour.refs.back.hidden and not tour.refs.skip.hidden, "no Back on the first page; Skip on every page")
t.assertEqual(tour.refs.dots.numberOfPages, #Tour.pages, "one dot per page")
t.assertEqual(tour.refs.dots.currentPage, 0, "the first dot is current")
tour:next()
t.assertEqual(tour.page, 2, "Continue moves on")
t.assertEqual(tour.refs.dots.currentPage, 1, "the dots follow")
t.expect(not tour.refs.page_2.hidden and not tour.refs.back.hidden, "the next page shows, with Back")
t.expect(tour.refs.page_1.hidden, "and the first one hides")
tour:show(#Tour.pages)
t.assertEqual(tour.refs.next.title, "Start Using Diskmap", "the last page closes the tour")
tour:show(3); tour:show(2)
t.expect(tour.refs.page_3.hidden and not tour.refs.page_2.hidden, "Back shows the previous page")
tour:show(99)
t.assertEqual(tour.page, #Tour.pages, "pages stay in range")
tour:next()
t.expect(tour.sheet == nil, "Start Using Diskmap closes it")
local again = Controller.new(service)
again:createWindow()
t.expect(again.tour.sheet ~= nil, "it shows on the next start while the box is checked")

-- Unchecking the box keeps it from showing on start; Skip closes it.
again.tour.refs.showOnStart.state = 0
again.tour:setShowOnStart(false)
again.tour:close()
local later = Controller.new(service)
later:createWindow()
t.expect(later.tour.sheet == nil, "unchecked, it does not show on start")
t.expect(later.tour:open(later.window) and later.tour.sheet ~= nil, "Help > Diskmap Tour opens it again")
t.assertEqual(later.tour.page, 1, "from the first page")
t.expect(later.tour.refs.showOnStart.state == 0, "the box shows the choice")
later.tour:setShowOnStart(true)
later.tour:close()
t.expect(later.tour:needed(), "checking it again brings it back on start")

-- After the access steps, the tour follows them.
local fresh = Mock.new()
local granted = false
fresh.hasFullDiskAccess = function() return granted end
fresh.openSettings = function() end
local first = Controller.new(fresh)
first:createWindow()
t.expect(first.onboarding.sheet ~= nil and first.tour.sheet == nil, "access comes first")
granted = true
first.onboarding:poll()
t.expect(first.onboarding.sheet == nil and first.tour.sheet ~= nil, "then the tour")

-- The synthetic disk has no access probe and never tours.
local demo = Controller.new(Mock.new())
demo:createWindow()
t.expect(demo.tour.sheet == nil, "no tour on the synthetic disk")

os.exit(t.summary() and 0 or 1)
