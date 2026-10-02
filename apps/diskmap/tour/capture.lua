-- Capture plan for the tour's screenshots, run on the showcase disk (the
-- synthetic Mock HDD with presentable names) by `make diskmap-tour-captures`,
-- so the tour never shows anyone's real files:
--
--   ./lua-objc --capture-plan=apps/diskmap/tour/capture.lua --width=1100 --height=688 \
--     apps/diskmap/init.lua --showcase
--
-- Each tour page shows only the element it explains, in light and dark, and
-- every image fills the tour's image box exactly: same proportions, and
-- twice its size in pixels. Elements reflow with the window, so the plan
-- first searches for the window width at which the element (with a margin)
-- has the box's proportions, then crops it there. What is left over, a few
-- points at most, is trimmed evenly from the margins of the longer side.
-- Elements are found by their template ids in the layout dump written with
-- each shot.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
-- BOX matches TOUR in views/sheets/Tour.etlua; tests/diskmap_tour.test.lua checks
-- every image against it.
local BOX = { width = 524, height = 290, scale = 2 }
local CROP = { margin = 12, quality = 92 }
-- `tolerance`: the most a final shot may differ from the box's proportions;
-- the difference is trimmed from the margins, so it must stay small.
local SEARCH = { minWidth = 780, maxWidth = 1560, height = 900, steps = 9, tolerance = 0.03 }

-- One shot per page of helpers/Tour.lua, named by its id. `ids`: the
-- elements cropped together; `maxHeight` in points keeps a long list to its
-- first rows, ending the crop at the last whole row; `height` is the window
-- height for pages whose content fills it.
local function page(id) return function(app) app:show(id) end end
local SHOTS = {
	{name = "overview", ids = {"heroCard"}, show = page("overview")},
	{name = "map", ids = {"mapBody"}, height = 645, show = page("map")},
	{name = "largest", ids = {"pageHeader", "largest"}, maxHeight = 330, show = page("largest")},
	{name = "files", ids = {"stats", "filesPanel"}, maxHeight = 400, show = page("files")},
	{name = "kinds", ids = {"kindsCard", "kinds"}, maxHeight = 400, show = page("kinds")},
	{name = "applications", ids = {"stats", "apps"}, maxHeight = 330, show = page("applications")},
	{name = "cleanup", ids = {"stats", "section_rebuildable"}, maxHeight = 421, show = page("cleanup")},
	{name = "developer", ids = {"section_xcode"}, show = page("developer")},
	{name = "disks", ids = {"health", "volumesSection"}, maxHeight = 380, show = page("disks")},
	{name = "guide", ids = {"topic_assets"}, show = function(app) app:search("guide", "Siri") end},
}

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

-- The elements' rectangle with its margin, in window points, and the dump's
-- pixels per point.
local function elementRect(layoutPath, shot)
	local file = assert(io.open(layoutPath, "r"))
	local dump = file:read("a"); file:close()
	local scale = tonumber(dump:match('<Layout scale="([%d.]+)"')) or 1
	local left, top, right, bottom
	for _, id in ipairs(shot.ids) do
		local x, y, w, h = dump:match('identifier="' .. id .. '"[^>]-window="([%d.-]+) ([%d.-]+) ([%d.-]+) ([%d.-]+)"')
		assert(x, shot.name .. ": no " .. id .. " in " .. layoutPath)
		x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
		left, top = math.min(left or x, x), math.min(top or y, y)
		right, bottom = math.max(right or x + w, x + w), math.max(bottom or y + h, y + h)
	end
	-- A list that fills the page runs on under the status bar; only what the
	-- page shows counts.
	local _, pageY, _, pageH = dump:match('identifier="page"[^>]-window="([%d.-]+) ([%d.-]+) ([%d.-]+) ([%d.-]+)"')
	if pageY then bottom = math.min(bottom, tonumber(pageY) + tonumber(pageH)) end
	local cut = shot.maxHeight and bottom > top + shot.maxHeight
	if cut then
		-- The last table row inside the elements that ends within the limit,
		-- so no row is cut. The sidebar's rows are outside them.
		local limit, last = top + shot.maxHeight, top
		for x, y, w, h in dump:gmatch('class="[%w_]*RowView" frame="[^"]*" window="([%d.-]+) ([%d.-]+) ([%d.-]+) ([%d.-]+)"') do
			x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
			local inside = x >= left and x + w <= right and y >= top
			if inside and y + h <= limit and y + h > last then last = y + h end
		end
		bottom = last > top and last or limit
	end
	local rect = {x = left - CROP.margin, y = top - CROP.margin, w = right - left + 2 * CROP.margin}
	rect.h = bottom - top + CROP.margin + (cut and 0 or CROP.margin)
	return rect, scale
end

local function measure(capture, app, shot, width, prefix)
	app.window:resize(width, shot.height or SEARCH.height)
	shot.show(app)
	capture.shot(prefix)
	return elementRect(prefix .. ".layout.xml", shot)
end

-- The window width whose element is closest to the box's proportions. An
-- element widens with the window and its text wraps less, so its aspect
-- ratio grows with the width and a bisection finds it.
local function fittingWidth(capture, app, shot, prefix)
	local target = BOX.width / BOX.height
	local low, high = SEARCH.minWidth, SEARCH.maxWidth
	local best, bestError
	for _ = 1, SEARCH.steps do
		local width = math.floor((low + high) / 2)
		local rect = measure(capture, app, shot, width, prefix)
		local aspect = rect.w / rect.h
		local error = math.abs(aspect - target) / target
		if not bestError or error < bestError then best, bestError = width, error end
		if aspect < target then low = width else high = width end
	end
	return best, bestError
end

-- Trims the longer side evenly to the box's proportions, crops, and scales
-- the pixels to exactly twice the box.
local function crop(prefix, rect, scale)
	local target = BOX.width / BOX.height
	if rect.w / rect.h > target then
		local width = rect.h * target
		rect.x, rect.w = rect.x + (rect.w - width) / 2, width
	else
		local height = rect.w / target
		rect.y, rect.h = rect.y + (rect.h - height) / 2, height
	end
	local function px(value) return math.floor(value * scale + 0.5) end
	assert(os.execute(string.format("/usr/bin/sips -c %d %d --cropOffset %d %d %s --out %s >/dev/null",
		px(rect.h), px(rect.w), px(rect.y), px(rect.x), quote(prefix .. ".png"), quote(prefix .. ".png"))))
	assert(os.execute(string.format("/usr/bin/sips -z %d %d -s format jpeg -s formatOptions %d %s --out %s >/dev/null",
		BOX.height * BOX.scale, BOX.width * BOX.scale, CROP.quality, quote(prefix .. ".png"), quote(prefix .. ".jpg"))))
	os.remove(prefix .. ".png"); os.remove(prefix .. ".layout.xml")
end

return function(capture, app)
	local widths = {}
	for _, appearance in ipairs({ "light", "dark" }) do
		capture.appearance(appearance)
		for _, shot in ipairs(SHOTS) do
			local prefix = here .. shot.name .. "-" .. appearance
			if not widths[shot.name] then
				local width, error = fittingWidth(capture, app, shot, prefix)
				widths[shot.name] = width
				print(string.format("%s: window %d pt wide, %.1f%% from the box's proportions", shot.name, width, error * 100))
			end
			local rect, scale = measure(capture, app, shot, widths[shot.name], prefix)
			local drift = math.abs(rect.w / rect.h - BOX.width / BOX.height) / (BOX.width / BOX.height)
			assert(drift < SEARCH.tolerance, string.format("%s %s: %.1f%% from the box's proportions", shot.name, appearance, drift * 100))
			crop(prefix, rect, scale)
		end
		app:search("guide", "")
	end
end
