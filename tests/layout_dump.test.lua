_G.__headless = true

local t = require("TestKit")
local path = os.tmpname() .. ".xml"
local command = string.format(
	"./lua-objc --dump-layout=%q examples/stocks/init.lua >/dev/null 2>&1", path)
local ok = os.execute(command)
t.expect(ok == true or ok == 0, "native layout dump command exits successfully")

local file = io.open(path, "r")
local dump = file and file:read("*a") or ""
if file then file:close() end
os.remove(path)

t.expect(dump:find('<View class="NSSearchField"', 1, true) ~= nil,
	"layout dump identifies native control classes")
t.expect(dump:find('<Column id="price"', 1, true) ~= nil,
	"layout dump includes computed quote columns")
t.expect(dump:find('cropped="', 1, true) ~= nil,
	"layout dump reports cell cropping explicitly")
t.expect(dump:find('insufficientTextSpace="true" ellipsis="true"', 1, true) ~= nil,
	"layout dump reports Cocoa text fields that will render an ellipsis")
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

os.exit(t.summary() and 0 or 1)
