-- Connects this Mac to your own Appwrite project (docs/backend.md), as Lua
-- Studio's Settings do on an iPad: an app whose <Backend> names no project
-- keeps its rows there and creates the tables it lacks at launch.
--
-- Create a project at https://cloud.appwrite.io (or on your own server) and
-- an API key with the scopes databases.read/write, tables.read/write,
-- columns.read/write and indexes.read/write. Then:
--
--   ./lua-objc scripts/appwrite/connect.lua https://fra.cloud.appwrite.io/v1 <project ID>
--   (paste the API key and press Return; it is read from the input, not the
--   command line, so it stays out of the shell's history)
--
--   ./lua-objc scripts/appwrite/connect.lua           shows the connected project
--   ./lua-objc scripts/appwrite/connect.lua --remove  forgets it
--
-- The three are kept in the Keychain entry `appwrite`, never in a file.
_G.__headless = true
local ns = require("AppKit")
local Connection = require("data.appwrite.connection")

local args = {...}
if #args == 0 and arg then args = {table.unpack(arg)} end
local connection = Connection.keychain(ns)

if args[1] == "--remove" then
	assert(connection:clear())
	print("The Appwrite connection is removed from the Keychain.")
	return
end

if #args == 0 then
	local saved = connection:load()
	print(saved and ("Connected to project " .. saved.project .. " at " .. saved.endpoint)
		or "No Appwrite project is connected. Usage: connect.lua <endpoint> <project ID>")
	return
end

local endpoint, project = args[1], args[2]
io.stderr:write("API key of project " .. tostring(project) .. ": ")
local key = io.read("l")
local saved, message = connection:save({endpoint = endpoint, project = project, key = key})
if not saved then
	io.stderr:write(message, "\n")
	os.exit(1)
end
print("Connected to project " .. saved.project .. " at " .. saved.endpoint .. ". The key is in the Keychain.")
