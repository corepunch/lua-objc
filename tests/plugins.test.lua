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
t.expect(failure("renamed"):find("declares id other but is named renamed", 1, true), "ids match their folders")
t.expect(failure("broken"):find("tests.fixtures.plugins.bad.broken", 1, true), "syntax errors name the plugin")
t.expect(failure("notable"):find("must return a manifest table", 1, true), "a plugin returns a manifest")
t.expect(failure("mistyped"):find("field title must be a string", 1, true), "manifest fields are type-checked")
t.expect(failure("absent"):find("not found", 1, true), "a missing plugin is an error, not a skip")
t.assertThrows(function() point:load("tests.fixtures.plugins.greeters", {"hello"}) end, "an id loads once")

-- Single-file plugins, as the lite editor's plugins/*.lua: a file beside
-- its siblings, its folder the shared one.
local files = Plugins.extensionPoint({name = "codec", api = 1, host = {upper = string.upper},
	manifest = {title = "string", encode = "function"}})
files:load("tests.fixtures.plugins.files", {"alpha", "beta"})
t.assertEqual(#files:list(), 2, "single-file plugins load in order")
t.assertEqual(files:get("alpha").file, "./tests/fixtures/plugins/files/alpha.lua", "a file plugin records its file")
t.assertEqual(files:get("alpha").directory, "tests/fixtures/plugins/files", "and shares the plugins folder for resources")
t.assertEqual(files:get("alpha").source, "bundled", "listed plugins are bundled")
t.assertEqual(files:invoke("alpha", "encode", "x"), "X", "invoke calls a manifest function with the host API first")
t.assertEqual(files:invoke("beta", "encode", "x"), "x-beta", "each file plugin keeps its own code")
t.assertThrows(function() files:invoke("alpha", "missing") end, "invoking an absent function raises")
t.assertThrows(function() files:invoke("gamma", "encode") end, "invoking an unknown plugin raises")

-- Plugins read by the host (dropped into a Documents folder) load from source.
local dropped = files:loadSource("gamma", 'return {api = 1, title = "Gamma", encode = function(host, v) return host.upper(v) .. "!" end}', "Plugins/gamma.lua")
t.assertEqual(dropped.source, "user", "a plugin from source is the user's")
t.assertEqual(dropped.file, "Plugins/gamma.lua", "and names its file")
t.assertEqual(files:invoke("gamma", "encode", "y"), "Y!", "a source plugin runs like any other")
t.assertEqual(files:index("gamma"), 3, "it joins the list after the bundled ones")
t.assertThrows(function() files:loadSource("gamma", "return {api = 1, title = 'Again'}") end, "a source plugin's id loads once")
local ok, err = pcall(files.loadSource, files, "delta", "return {api = 1}", "Plugins/delta.lua")
t.expect(not ok and tostring(err):find("Plugins/delta.lua is missing required field", 1, true), "a source plugin's errors name its file")
ok, err = pcall(files.loadSource, files, "epsilon", "return {api = 1, title = 'E', encode = function() return require('os') end}", "Plugins/epsilon.lua")
t.expect(ok and not pcall(files.invoke, files, "epsilon", "encode"), "a source plugin cannot require")
ok, err = pcall(files.loadSource, files, "zeta", "this is not lua", "Plugins/zeta.lua")
t.expect(not ok and tostring(err):find("Plugins/zeta.lua", 1, true), "a syntax error names the file")

-- File names in a plugins folder become ids.
t.assertEqual(Plugins.pluginName("openai.lua"), "openai", "a .lua file is a plugin")
t.assertEqual(Plugins.pluginName("my-gateway_2.lua"), "my-gateway_2", "ids may carry dashes, underscores and digits")
t.assertEqual(Plugins.pluginName("README.md"), nil, "other files are not plugins")
t.assertEqual(Plugins.pluginName("_disabled.lua"), nil, "an underscore switches a plugin off")
t.assertEqual(Plugins.pluginName(".hidden.lua"), nil, "hidden files are skipped")
t.assertEqual(Plugins.pluginName("folder"), nil, "a folder name is not a file plugin")
t.assertThrows(function() Plugins.extensionPoint({name = "x", api = 1, manifest = {id = "string"}}) end,
	"id is reserved for the host")
t.assertThrows(function() Plugins.extensionPoint({name = "x", api = "1"}) end, "api versions are integers")

os.exit(t.summary() and 0 or 1)
