-- Writes the appwrite.json of an app's remote models, for the Appwrite CLI:
--
--   ./lua-objc scripts/appwrite/schema.lua demo/notes build/notes.appwrite.json
--   appwrite push tables --config build/notes.appwrite.json
--
-- The project, endpoint and database come from the app's `<Backend>`
-- (app.xml), or from the project connected on this Mac when it names none
-- (scripts/appwrite/connect.lua); the tables from every model in its models/ folder, loaded
-- headlessly. The file is generated, never committed: the models are the
-- source (docs/backend.md).
_G.__headless = true
local Manifest = require("data.manifest")
local Model = require("data.model")
local Schema = require("data.appwrite.schema")
local Connection = require("data.appwrite.connection")

local args = {...}
if #args == 0 and arg then args = {table.unpack(arg)} end
local dir, out = args[1], args[2]
assert(dir and out, "usage: schema.lua <app folder> <appwrite.json>")
dir = dir:gsub("/+$", "")

local manifest = Manifest.load(dir .. "/app.xml")
assert(manifest.backend, dir .. "/app.xml has no <Backend>")
local backend = manifest.backend
if backend.connected then
	local connected = Connection.keychain(require("AppKit")):load()
	assert(connected, dir .. "/app.xml saves to the connected Appwrite project and none is connected: "
		.. "run scripts/appwrite/connect.lua")
	backend.project, backend.endpoint = connected.project, connected.endpoint
end

-- Every model file of the app, so each remote model registers its table.
local module = dir:gsub("/", ".")
local listing = assert(io.popen('ls "' .. dir .. '/models" 2>/dev/null'))
for name in listing:lines() do
	local model = name:match("^(.+)%.lua$")
	if model then require(module .. ".models." .. model) end
end
listing:close()

local config = Schema.config({
	project = backend.project,
	endpoint = backend.endpoint,
	database = backend.database,
	models = Model.models,
})
local file = assert(io.open(out, "w"))
file:write(Schema.encode(config), "\n")
file:close()
print(string.format("%s: %d tables in database %s of project %s", out, #config.tables,
	backend.database, backend.project))
