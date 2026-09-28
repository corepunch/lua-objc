_G.__headless = true
local t = require("TestKit")
local Plugins = require("Plugins")

local host = {decorate = function(text) return "«" .. text .. "»" end, palette = {"red", "green"}}
local function greeters()
	return Plugins.extensionPoint({
		name = "greeter", api = 1, host = host,
		manifest = {title = "string", symbol = "string?", create = "function"},
	})
end

-- Loading, order and manifests.
local point = greeters():load("tests.fixtures.plugins.greeters", {"shout", "hello"})
local list = point:list()
t.assertEqual(#list, 2, "every listed plugin loads")
t.assertEqual(list[1].id, "shout", "plugins keep the order they were listed in")
t.assertEqual(list[2].title, "Hello", "manifest fields are read without running the factory")
t.assertEqual(list[2].symbol, nil, "optional fields may be omitted")
t.assertEqual(point:get("shout").symbol, "megaphone", "plugins are found by id")
t.expect(point:get("shout").extra.loud, "undeclared manifest fields are kept for the plugin's own use")
t.assertEqual(point:index("hello"), 2, "index gives a plugin's position for pickers")
t.assertEqual(point:get("hello").directory, "tests/fixtures/plugins/greeters/hello", "the folder is derived from the module")
t.assertEqual(package.loaded["tests.fixtures.plugins.greeters.hello"], nil, "plugins never enter package.loaded")

-- Factories and the host API.
local hello = point:create("hello", "Ada")
t.assertEqual(hello.text, "«Hello, Ada»", "create receives the shared host services")
t.assertEqual(hello.folder, "tests/fixtures/plugins/greeters/hello", "and the plugin's own context")
t.assertEqual(hello.art, "tests/fixtures/plugins/greeters/hello/art.png", "resource paths resolve inside the plugin folder")
local first, second = point:create("shout", "hi"), point:create("shout", "hey")
t.assertEqual(first.text, "«HI»", "a plugin may use its own copy of the string library")
t.assertEqual(second.count, 2, "plugin globals persist in the plugin's environment between calls")
t.expect(first.hasMath, "pure standard libraries are available")
t.assertEqual(rawget(_G, "counter"), nil, "plugin globals never leak into the app")
t.assertThrows(function() point:create("missing") end, "creating an unknown plugin raises")

-- The host API is read-only.
local view = Plugins.readonly(host)
t.assertThrows(function() view.decorate = nil end, "plugins cannot replace host services")
t.assertThrows(function() view.palette[1] = "blue" end, "nested host tables are read-only too")
t.assertEqual(view.palette[2], "green", "reads pass through")
t.assertEqual(#view.palette, 2, "length passes through")
local seen = {}
for _, colour in ipairs(view.palette) do table.insert(seen, colour) end
t.assertEqual(table.concat(seen, ","), "red,green", "ipairs walks the host table")
local keys = 0
for key in pairs(view) do keys = keys + 1; t.expect(host[key] ~= nil, "pairs yields host keys") end
t.assertEqual(keys, 2, "pairs walks every host key")
t.assertEqual(Plugins.readonly(view), view, "a read-only view is not wrapped twice")
t.assertEqual(host.palette[1], "red", "the host's own table is untouched")

-- Isolation.
local bad = Plugins.extensionPoint({name = "probe", api = 1, manifest = {title = "string"}})
bad:load("tests.fixtures.plugins.bad", {"escape"})
local found = bad:get("escape").found
for _, name in ipairs({"require", "io", "os", "load", "debug", "package", "dofile"}) do
	t.assertEqual(found[name], nil, name .. " is not reachable from a plugin")
end

-- Contract violations name the plugin.
local function failure(name)
	local ok, err = pcall(function()
		Plugins.extensionPoint({name = "probe", api = 1, manifest = {title = "string"}})
			:load("tests.fixtures.plugins.bad", {name})
	end)
	t.expect(not ok, name .. " is rejected")
	return tostring(err)
end
t.expect(failure("oldapi"):find("targets api 0; this host provides api 1", 1, true), "an API version mismatch is explained")
t.expect(failure("renamed"):find("declares id other but lives in folder renamed", 1, true), "ids match their folders")
t.expect(failure("broken"):find("tests.fixtures.plugins.bad.broken", 1, true), "syntax errors name the plugin")
t.expect(failure("notable"):find("must return a manifest table", 1, true), "a plugin returns a manifest")
t.expect(failure("mistyped"):find("field title must be a string", 1, true), "manifest fields are type-checked")
t.expect(failure("absent"):find("not found", 1, true), "a missing plugin is an error, not a skip")
t.assertThrows(function() point:load("tests.fixtures.plugins.greeters", {"hello"}) end, "an id loads once")
t.assertThrows(function() Plugins.extensionPoint({name = "x", api = 1, manifest = {id = "string"}}) end,
	"id is reserved for the host")
t.assertThrows(function() Plugins.extensionPoint({name = "x", api = "1"}) end, "api versions are integers")

os.exit(t.summary() and 0 or 1)
