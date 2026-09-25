_G.__headless = true

-- The MVC contract in AGENTS.md, enforced for every app, demo and test app.
-- Rules are checked from source so a violation fails `make test` before
-- review instead of relying on convention.

local t = require("TestKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

local ROOTS = { "apps", "demo", "test" }
-- Platform module names an app may bind; `self.ns` and injected `ns` match too.
local PLATFORM = { "ns", "AppKit", "UIKit" }

local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

local function entries(path)
	local ok, list = pcall(bridge._listDirectory, path)
	return ok and list or {}
end

local function walk(path, visit)
	for _, entry in ipairs(entries(path)) do
		if entry.directory then walk(entry.path, visit) else visit(entry) end
	end
end

-- Code without comments or long strings (embedded sample code).
local function stripped(source)
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
	return (source:gsub("%[(=*)%[.-%]%1%]", '""'))
end

-- Code without comments or any string literal, so prose never matches.
local function code(source)
	source = stripped(source)
	return (source:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''"))
end

-- Every XML tag and the platform constructor it maps to is a view constructor.
local viewConstructors = {}
for tag in pairs(xml.registry) do viewConstructors[tag] = true end
for tag, schema in pairs(xml.schema) do
	viewConstructors[tag] = true
	if type(schema) == "table" and schema.constructor then viewConstructors[schema.constructor] = true end
end

local function constructorCalls(source)
	local calls = {}
	source = code(source)
	for _, module in ipairs(PLATFORM) do
		for name in source:gmatch("%f[%w_]" .. module .. "%.(%u[%w_]*)%s*[%({]") do
			if viewConstructors[name] then calls[name] = true end
		end
	end
	return calls
end

local function luaFiles(root, folder)
	local files = {}
	walk(root .. "/" .. folder, function(entry)
		if entry.name:match("%.lua$") then table.insert(files, entry.path) end
	end)
	return files
end

local function exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

local apps = {}
for _, base in ipairs(ROOTS) do
	for _, entry in ipairs(entries(base)) do
		-- Empty folders are scratch output, not apps.
		if entry.directory and #entries(entry.path) > 0 then table.insert(apps, entry.path) end
	end
end
table.sort(apps)
t.expect(#apps >= 30, "architecture scan finds the apps, demos and test apps")

-- Existing violations, each to be fixed by moving view code into etlua
-- templates and IO into injected services. This list may only shrink: a
-- new violation fails, and so does an entry that no longer occurs.
local KNOWN = {
	["apps/stocks/Controller.lua constructs ns.List"] = true,
	["apps/stocks/Controller.lua constructs ns.SearchField"] = true,
	["apps/stocks/Controller.lua constructs ns.VStack"] = true,
	["apps/stocks/Model.lua requires \"AppKit\""] = true,
	["apps/stocks/Model.lua references ns"] = true,
	["apps/weather/Controller.lua constructs ns.List"] = true,
	["apps/weather/Controller.lua constructs ns.VStack"] = true,
	["apps/weather/Model.lua requires \"AppKit\""] = true,
	["apps/weather/Model.lua references ns"] = true,
	["demo/ide/Controller.lua constructs ns.MenuItem"] = true,
	["demo/ide/Controller.lua constructs ns.OutlineView"] = true,
	["demo/ide/Controller.lua constructs ns.TextEditor"] = true,
	["demo/ide/Model.lua requires \"AppKit\""] = true,
	["demo/ide/Model.lua references ns"] = true,
	["demo/layout/Controller.lua constructs ns.List"] = true,
	["demo/list/Controller.lua constructs ns.List"] = true,
	["demo/list/Controller.lua constructs ns.VStack"] = true,
	["demo/mail/Controller.lua constructs ns.List"] = true,
	["demo/mail/Controller.lua constructs ns.VStack"] = true,
	["demo/phone-tabs/views/Tabs.lua is not an etlua template"] = true,
	["demo/snippets/Controller.lua constructs ns.Button"] = true,
	["demo/snippets/Controller.lua constructs ns.HStack"] = true,
	["demo/snippets/Controller.lua constructs ns.List"] = true,
	["demo/snippets/Controller.lua constructs ns.Picker"] = true,
	["demo/snippets/Controller.lua constructs ns.SearchField"] = true,
	["demo/snippets/Controller.lua constructs ns.TextEditor"] = true,
	["demo/snippets/Controller.lua constructs ns.VStack"] = true,
	["demo/welcome/Controller.lua constructs ns.VStack"] = true,
}

local violations = {}
local function check(ok, violation)
	if not ok then violations[violation] = true end
end

for _, app in ipairs(apps) do
	local module = app:gsub("/", ".")

	-- init.lua is the entry point only: it returns the Controller class.
	local initPath = app .. "/init.lua"
	check(exists(initPath), app .. " has no init.lua")
	if exists(initPath) then
		local source = stripped(read(initPath)):gsub("%s+", " "):match("^%s*(.-)%s*$")
		check(source == 'return require("' .. module .. '.Controller")',
			app .. '/init.lua does more than return require("' .. module .. '.Controller")')
	end

	check(exists(app .. "/Controller.lua"), app .. " has no Controller.lua")
	local ok, class = pcall(dofile, initPath)
	check(ok and type(class) == "table" and type(class.new) == "function"
		and type(class.createWindow) == "function",
		app .. " entry does not return a class with new() and createWindow()")

	-- Views are etlua templates only.
	walk(app .. "/views", function(entry)
		check(entry.name:match("%.etlua$") ~= nil, entry.path .. " is not an etlua template")
	end)

	-- Models own domain data; they never touch the platform. IO belongs in
	-- injected services.
	local models = luaFiles(app, "models")
	if exists(app .. "/Model.lua") then table.insert(models, app .. "/Model.lua") end
	for _, path in ipairs(models) do
		local source = stripped(read(path))
		for _, platform in ipairs(PLATFORM) do
			check(not source:find('require%s*%(?%s*["\']' .. platform .. '["\']'),
				path .. ' requires "' .. platform .. '"')
		end
		check(not code(source):find("%f[%w_]ns%."), path .. " references ns")
	end

	-- Controllers render templates; they never construct views. Only the
	-- root Controller creates the Window.
	local controllers = luaFiles(app, "controllers")
	table.insert(controllers, app .. "/Controller.lua")
	for _, path in ipairs(controllers) do
		if exists(path) then
			for name in pairs(constructorCalls(read(path))) do
				check(name == "Window" and path == app .. "/Controller.lua",
					path .. " constructs ns." .. name)
			end
		end
	end
	for _, path in ipairs(luaFiles(app, "services")) do
		check(not constructorCalls(read(path)).Window, path .. " constructs ns.Window")
	end
end

for violation in pairs(violations) do
	t.expect(KNOWN[violation], "MVC contract: " .. violation)
end
for violation in pairs(KNOWN) do
	t.expect(violations[violation], "fixed violation must leave KNOWN: " .. violation)
end

-- The scanner itself must catch what it claims to catch.
t.expect(constructorCalls("local v = self.ns.VStack { }").VStack, "detects injected-ns constructors")
t.expect(constructorCalls("AppKit.Button({})").Button, "detects module-qualified constructors")
t.expect(next(constructorCalls('-- ns.VStack {}\nlocal s = "ns.Text()"')) == nil,
	"ignores comments and strings")
t.expect(next(constructorCalls("ns.Font { size = 12 }; ns.Color('primary')")) == nil,
	"value constructors are not views")

os.exit(t.summary() and 0 or 1)
