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

t.expect(dump:find('<View class="NSSearchField"', 1, true) ~= nil,
	"layout dump identifies native control classes")
t.expect(dump:find('<View class="NSSearchField" x="8.0" y="0.0" width="326.0" height="36.0"',
	1, true) ~= nil,
	"layout dump proves the extra-large search field is pinned high in its inset wrapper")
t.expect(dump:find('<Column id="price"', 1, true) ~= nil,
	"layout dump includes computed quote columns")
t.expect(dump:find('<Column id="symbol" width="131.0"', 1, true) ~= nil,
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
t.expect(dump:find('<View class="LuaPathView" x="4.0" y="10.0"', 1, true) ~= nil,
	"layout dump proves a daily sparkline is mounted in a stock row")
t.expect(dump:find('text="Open"', 1, true) ~= nil
	and dump:find('text="52W H"', 1, true) ~= nil,
	"layout dump exposes the aligned stock metric columns")
t.expect(dump:find('text="Related News"', 1, true) ~= nil,
	"layout dump exposes the related-news grid")
t.expect(dump:find('outsideParent="', 1, true) ~= nil,
	"layout dump reports view overflow explicitly")
t.expect(dump:match('<View class="NSView" x="0.0" y="0.0" width="[%d.]+" height="[%d.]+" windowX="0.0" windowY="0.0"') ~= nil,
	"layout dump places the root at the window origin")

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
local width, height, windowX, windowY = treemap:match('identifier="treemap" x="[%d.]+" y="[%d.]+" '
	.. 'width="([%d.]+)" height="([%d.]+)" windowX="([%d.]+)" windowY="([%d.]+)"')
width, height, windowX, windowY = tonumber(width), tonumber(height), tonumber(windowX), tonumber(windowY)
t.expect(width ~= nil and windowX > 0 and windowY > 0 and windowY + height < 900,
	"a view inside unflipped stacks reports a top-left window origin")
local cellX, cellY = treemap:match('<TreemapCell id="[^"]+" depth="0" windowX="([%d.]+)" windowY="([%d.]+)"')
t.expect(cellX ~= nil and tonumber(cellX) == windowX and tonumber(cellY) == windowY,
	"the first top-level treemap cell starts at the treemap's window origin")

os.exit(t.summary() and 0 or 1)
