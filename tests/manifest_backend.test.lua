-- <Backend> in the app manifest (lua/data/manifest.lua) and the script that
-- writes an app's appwrite.json (scripts/appwrite/schema.lua).
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Manifest = require("data.manifest")
local Development = require("data.appwrite.development")

local function parse(backend)
	return Manifest.parse(xml.parse('<App name="A">' .. backend .. '<Page id="home" title="Home" /></App>'))
end

local function refuses(backend, fragment, label)
	local ok, err = pcall(parse, backend)
	t.expect(not ok and tostring(err):find(fragment, 1, true) ~= nil, label .. ": " .. tostring(err))
end

t.assertEqual(parse("").backend, nil, "an app without <Backend> stays local")

local own = parse('<Backend provider="appwrite" endpoint="https://fra.cloud.appwrite.io/v1" project="69f1c06800389dc6a1a0" database="notes" />').backend
t.expect(own.provider == "appwrite" and own.project == "69f1c06800389dc6a1a0" and own.database == "notes"
	and own.endpoint == "https://fra.cloud.appwrite.io/v1" and own.development == false, "an app's own project")

refuses('<Backend endpoint="https://x/v1" project="p" />', 'provider="appwrite"', "the provider is named")
refuses('<Backend provider="firebase" />', 'provider="appwrite"', "Appwrite is the provider")
refuses('<Backend provider="appwrite" project="p" />', "names its endpoint", "an own project names its endpoint")
refuses('<Backend provider="appwrite" project="p" endpoint="fra.cloud.appwrite.io" />', "names its endpoint",
	"the endpoint is a URL")
refuses('<Backend provider="appwrite" project="a/b" endpoint="https://x/v1" />', "not an Appwrite project ID",
	"a project ID is one path segment")
refuses('<Backend provider="appwrite" project="p" endpoint="https://x/v1" database="../x" />', "not an Appwrite database ID",
	"a database ID is one path segment")
refuses('<Backend provider="appwrite" project="p" endpoint="https://x/v1" key="secret" />', "has no attribute key",
	"a backend takes no key: secrets never go in the manifest")
refuses('<Backend provider="appwrite" project="p" endpoint="https://x/v1" /><Backend provider="appwrite" project="q" endpoint="https://x/v1" />',
	"one <Backend>", "an app has one backend")
refuses('<Backend provider="appwrite" endpoint="https://elsewhere/v1" />', "names no endpoint",
	"the development project has its own endpoint")

-- The development project: named in one file, used when no project is given.
local saved = Development.project
Development.project = nil
refuses('<Backend provider="appwrite" />', "development.lua", "without the development project's ID the error says where it goes")
Development.project = "dev-project"
local dev = parse('<Backend provider="appwrite" />').backend
t.expect(dev.project == "dev-project" and dev.endpoint == Development.endpoint and dev.development == true,
	"no project is the development project")
Development.project = saved

-- The database defaults to the app's folder.
local fixture = Manifest.load("tests/fixtures/backend/app.xml")
t.assertEqual(fixture.backend.database, "backend", "the database is named after the app folder")
t.assertEqual(fixture.pages.items.title, "Items", "pages still parse beside <Backend>")

-- The schema script writes the app's appwrite.json from its models.
local out = os.tmpname()
local command = "./lua-objc scripts/appwrite/schema.lua tests/fixtures/backend " .. out .. " 2>&1"
local pipe = assert(io.popen(command))
local printed = pipe:read("a")
local ok = pipe:close()
t.expect(ok, "the schema script succeeds: " .. printed)
t.expect(printed:find("1 tables in database backend of project fixture-project", 1, true) ~= nil,
	"it reports what it wrote: " .. printed)
local file = io.open(out)
local config = file and ns.json_parse(file:read("a"))
if file then file:close() end
os.remove(out)
t.expect(config and config.projectId == "fixture-project" and config.endpoint == "https://fra.cloud.appwrite.io/v1",
	"the file names the manifest's project and endpoint")
t.expect(config and config.tablesDB[1]["$id"] == "backend" and #config.tables == 1 and config.tables[1]["$id"] == "fixture_items",
	"one table per remote model of the app; local models are none")
t.expect(config and config.tables[1].indexes[1].columns[1] == "$createdAt", "the models' indexes reach the file")

local failed = io.popen("./lua-objc scripts/appwrite/schema.lua demo/storage " .. out .. " 2>&1")
local message = failed:read("a")
t.expect(not failed:close() and message:find("has no <Backend>", 1, true) ~= nil, "an app without a backend has no schema")
os.remove(out)

os.exit(t.summary() and 0 or 1)
