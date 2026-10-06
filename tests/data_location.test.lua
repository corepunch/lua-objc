_G.__headless = true
-- Page locations read like URLs: the page, its argument, then a sorted query.
local t = require("TestKit")
local Location = require("data.location")

local pages = {
	overview = {id = "overview", attrs = {}},
	help = {id = "help", attrs = {arg = "topic"}},
	files = {id = "files", attrs = {arg = "filter"}},
	folder = {id = "folder", attrs = {arg = "path"}},
}
local function roundTrip(page, params, expected, message)
	local text = Location.format(pages[page], params)
	t.assertEqual(text, expected, message)
	local id, parsed = Location.parse(text, pages)
	t.assertEqual(id, page, message .. ": page")
	for name, value in pairs(params) do t.assertEqual(parsed[name], tostring(value), message .. ": " .. name) end
	local count = 0; for _ in pairs(parsed) do count = count + 1 end
	local wanted = 0; for _ in pairs(params) do wanted = wanted + 1 end
	t.assertEqual(count, wanted, message .. ": no other params")
end

roundTrip("overview", {}, "/overview", "a page without params is its id")
roundTrip("help", {topic = "shortcuts"}, "/help/shortcuts", "the argument follows the page")
roundTrip("files", {filter = "Installers & archives", kind = "video"}, "/files/Installers%20%26%20archives?kind=video",
	"other params form the query and reserved characters are escaped")
roundTrip("folder", {path = "/Users/me/My Music"}, "/folder//Users/me/My%20Music", "a path keeps its slashes")
roundTrip("folder", {path = "/"}, "/folder//", "the startup disk is the root path")
roundTrip("folder", {path = "/a", focus = "/a/b?c"}, "/folder//a?focus=%2Fa%2Fb%3Fc", "query values escape slashes and marks")
roundTrip("overview", {b = 2, a = 1}, "/overview?a=1&b=2", "the query is sorted, so one place is one string")
t.assertEqual(Location.format(pages.help, {}), "/help", "a missing argument leaves the path short")

t.assertThrows(function() Location.parse("/nope", pages) end, "an unknown page is an error")
t.assertThrows(function() Location.parse("overview", pages) end, "a location starts with a slash")
t.assertThrows(function() Location.parse("/overview/extra", pages) end, "a page without an argument takes none")
local _, empty = Location.parse("/help", pages)
t.assertEqual(next(empty), nil, "a page shown without its argument has no params")

os.exit(t.summary() and 0 or 1)
