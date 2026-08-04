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
	"layout dump includes computed table columns")
t.expect(dump:find('cropped="', 1, true) ~= nil,
	"layout dump reports cell cropping explicitly")
t.expect(dump:match('column="price"[^>]-cropped="false"') ~= nil,
	"layout dump proves a computed stock price cell is not cropped")
t.expect(dump:match('column="change"[^>]-cropped="false"') ~= nil,
	"layout dump proves a computed stock change cell is not cropped")
t.expect(dump:find('outsideParent="', 1, true) ~= nil,
	"layout dump reports view overflow explicitly")

os.exit(t.summary() and 0 or 1)
