local Model = require("data.model")
local Provider = {}

-- The service as one window sees it. A window reads its own store
-- (lua/data/model.lua binds one at a time), and Diskmap can show two windows
-- (an opened scan beside this Mac): every function the service calls back
-- later, a scan's progress or a measurement's sizes, runs with that window's
-- store bound again. Assignments reach the service itself.
function Provider.bind(service, store)
	return setmetatable({}, {__index = function(_, key)
		local value = service[key]
		if type(value) ~= "function" then return value end
		return function(...)
			local arguments = table.pack(...)
			for index = 1, arguments.n do
				if type(arguments[index]) == "function" then arguments[index] = Model.bound(store, arguments[index]) end
			end
			return value(table.unpack(arguments, 1, arguments.n))
		end
	end, __newindex = service, service = service})
end

-- What the service itself offers under `name`, without asking a strict test
-- double for a feature it lacks (rawget): nil when it has none. A function
-- comes back bound like any other call of the window's service.
function Provider.offers(service, name)
	local meta = getmetatable(service)
	local target = meta and meta.service or service
	local value = rawget(target, name)
	if type(value) == "function" and target ~= service then return service[name] end
	return value
end

local function argumentValue(arguments, flag)
	for index, argument in ipairs(arguments or {}) do
		if argument == flag then return arguments[index + 1] end
		local prefix = flag .. "="
		if type(argument) == "string" and argument:sub(1, #prefix) == prefix then return argument:sub(#prefix + 1) end
	end
end

-- A one-time export lives outside the repo so personal paths are not committed.
-- Headless tests keep the bundled synthetic fixture.
function Provider.savedSnapshotPath()
	return require("apps.diskmap.services.System").supportPath("mock-hdd.bin")
end

local function savedSnapshot()
	if _G.__headless then return nil end
	local path = Provider.savedSnapshotPath()
	local file = io.open(path, "rb")
	if not file then return nil end
	file:close()
	return require("apps.diskmap.services.Mock").new({fixturePath = path})
end

function Provider.select(arguments)
	for _, argument in ipairs(arguments or {}) do
		if argument == "--showcase" then return require("apps.diskmap.services.Mock").new({showcase = true}) end
	end
	local fixturePath = argumentValue(arguments, "--mock-file") or argumentValue(arguments, "-mock-file")
	if fixturePath then return require("apps.diskmap.services.Mock").new({fixturePath = fixturePath}) end
	for _, argument in ipairs(arguments or {}) do
		if argument == "--mock" or argument == "-mock" then
			return savedSnapshot() or require("apps.diskmap.services.Mock").new()
		end
	end
	return require("apps.diskmap.services.System")
end

-- `--page=<id>` opens a sidebar destination at launch, so screenshots and
-- walkthroughs can start on any page.
function Provider.page(arguments)
	return argumentValue(arguments, "--page")
end

-- `--map-style=rectangles` opens the Map as a treemap.
function Provider.mapStyle(arguments)
	return argumentValue(arguments, "--map-style")
end

-- `--folder=<path>` opens a folder or disk on the Folder Map page at launch,
-- as dropping it on the Dock icon does.
function Provider.folder(arguments)
	return argumentValue(arguments, "--folder")
end

function Provider.exportPath(arguments)
	return argumentValue(arguments, "--export-mock")
end

return Provider
