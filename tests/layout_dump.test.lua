_G.__headless = true

local t = require("TestKit")
local path = os.tmpname() .. ".xml"
local command = string.format(
	"./lua-objc --dump-layout=%q apps/stocks/init.lua >/dev/null 2>&1", path)
local ok = os.execute(command)
t.expect(ok == true or ok == 0, "native layout dump command exits successfully")

local file = io.open(path, "r")
local dump = file and file:read("*a") or ""
if file then file:close() end
os.remove(path)

t.expect(dump:match('<Layout scale="%d+">') ~= nil,
	"layout dump records the backing scale that --capture images use")
t.expect(dump:find('<View class="NSSearchField"', 1, true) ~= nil,
	"layout dump identifies native control classes")
t.expect(dump:find('<View class="NSSearchField" frame="8 0 326 36"',
	1, true) ~= nil,
	"layout dump proves the extra-large search field is pinned high in its inset wrapper")
t.expect(dump:find('<Column id="price"', 1, true) ~= nil,
	"layout dump includes computed quote columns")
t.expect(dump:find('<Column id="symbol" width="131"', 1, true) ~= nil,
	"layout dump proves the edge-to-edge list gives spare width to stock names")
t.expect(dump:find('cropped="', 1, true) ~= nil,
	"layout dump reports cell cropping explicitly")
t.expect(dump:match('contentClipped="false" insufficientTextSpace="false" '
	.. 'ellipsis="false" text="NASDAQ Composite"') ~= nil,
	"layout dump proves NASDAQ Composite uses the recovered sidebar width")
t.expect(dump:match('row="1" column="price"[^>]-cropped="false"[^>]-ellipsis="false"') ~= nil,
	"layout dump proves computed stock quotes do not receive ellipses")
t.expect(dump:find('<Column id="chartData"', 1, true) ~= nil,
	"layout dump includes the daily sparkline column")
t.expect(dump:find('<View class="LuaPathView" frame="4 10 ', 1, true) ~= nil,
	"layout dump proves a daily sparkline is mounted in a stock row")
t.expect(dump:find('text="Open"', 1, true) ~= nil
	and dump:find('text="52W H"', 1, true) ~= nil,
	"layout dump exposes the aligned stock metric columns")
t.expect(dump:find('text="Related News"', 1, true) ~= nil,
	"layout dump exposes the related-news grid")
t.expect(dump:find('outsideParent="', 1, true) ~= nil,
	"layout dump reports view overflow explicitly")
t.expect(dump:match('<View class="NSView" frame="0 0 [%d.]+ [%d.]+" window="0 0 ') ~= nil,
	"layout dump places the root at the window origin")
for _, name in ipairs({ "frame", "window", "intrinsic", "fitting", "width", "x" }) do
	t.expect(dump:match(" " .. name .. '="[-%d. ]-%d%.0[ "]') == nil,
		"layout dump writes whole " .. name .. " points without a trailing .0")
end

-- Window frames are top-left window points, matching a window capture, and
-- treemap cells are listed with them (the Reel package cuts pieces by id).
local treemapPath = os.tmpname() .. ".xml"
ok = os.execute(string.format("./lua-objc --dump-layout=%q --width=1440 --height=900 "
	.. "apps/diskmap/init.lua --showcase --page=map --map-style=rectangles >/dev/null 2>&1", treemapPath))
t.expect(ok == true or ok == 0, "Diskmap treemap layout dump exits successfully")
file = io.open(treemapPath, "r")
local treemap = file and file:read("*a") or ""
if file then file:close() end
os.remove(treemapPath)
local windowX, windowY, width, height = treemap:match('identifier="treemap" frame="[^"]+" '
	.. 'window="([%d.]+) ([%d.]+) ([%d.]+) ([%d.]+)"')
width, height, windowX, windowY = tonumber(width), tonumber(height), tonumber(windowX), tonumber(windowY)
t.expect(width ~= nil and windowX > 0 and windowY > 0 and windowY + height < 900,
	"a view inside unflipped stacks reports a top-left window origin")
local cellX, cellY = treemap:match('<TreemapCell id="[^"]+" depth="0" window="([%d.]+) ([%d.]+) ')
local margin = require("ui.treemap").metrics.margin
t.expect(cellX ~= nil and tonumber(cellX) == windowX + margin and tonumber(cellY) == windowY + margin,
	"the first top-level treemap cell starts one margin inside the treemap's window origin")

local rects = {}
for _, isolated in ipairs({false, true}) do
	local workspacePath = os.tmpname() .. ".xml"
	ok = os.execute(string.format("./lua-objc --dump-layout=%q --width=1100 --height=760 "
		.. "apps/diskmap/init.lua --showcase --page=xcode%s >/dev/null 2>&1", workspacePath, isolated and " --isolated" or ""))
	t.expect(ok == true or ok == 0, "Xcode workspace dump exits successfully")
	file = io.open(workspacePath, "r")
	local workspace = file and file:read("*a") or ""
	if file then file:close() end
	os.remove(workspacePath)
	t.assertEqual(workspace:find('identifier="sidebar"', 1, true) ~= nil, not isolated, "isolated workspace omits the sidebar")
	local x, y, w, h = workspace:match('identifier="page" frame="[^"]+" window="([%d.]+) ([%d.]+) ([%d.]+) ([%d.]+)"')
	table.insert(rects, {x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h)})
end
t.expect(rects[2].x == 0 and rects[2].w == 1100, "isolated content uses the full window width")
t.expect(rects[1].y ~= nil and rects[1].y > 0 and rects[1].y == rects[2].y, "both workspace panes respect the same native toolbar safe area")
t.assertEqual(rects[1].h, rects[2].h, "both workspace panes have the same available height")

os.exit(t.summary() and 0 or 1)
