local Model = require("data.model")
local Provider = {}

-- The service as one window sees it. A window reads its own store
-- (lua/data/model.lua binds one at a time), and Diskmap can show two windows
-- (an opened scan beside this Mac): every function the service calls back
-- later, a scan's progress or a measurement's sizes, runs with that window's
-- store bound again. Assignments reach the service itself.
function Provider.bind(service, store, promptParent)
	return setmetatable({}, {__index = function(_, key)
		local value = service[key]
		if type(value) ~= "function" then return value end
		return function(...)
			local arguments = table.pack(...)
			if promptParent and (key == "confirmAction" or key == "confirmTrash" or key == "confirmEmptyTrash" or key == "confirmOwnerCleanup" or key == "confirmTrashPath" or key == "showError" or key == "requestDiskAccess") then
				arguments.n = arguments.n + 1; arguments[arguments.n] = promptParent()
			end
			for index = 1, arguments.n do
				if type(arguments[index]) == "function" then arguments[index] = Model.bound(store, arguments[index]) end
			end
			return value(table.unpack(arguments, 1, arguments.n))
		end
	end, __newindex = service, service = service})
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

-- Process flags are consumed once. A second window supplies an empty launch
-- table and never repeats an export or opens the process's initial folder.
function Provider.launch(arguments, service)
	local launch = {page = argumentValue(arguments, "--page"), folder = argumentValue(arguments, "--folder"),
		mapStyle = argumentValue(arguments, "--map-style"), exportPath = argumentValue(arguments, "--export-mock")}
	for _, argument in ipairs(arguments or {}) do
		if argument == "--isolated" then launch.isolated = true end
	end
	local manifest = require("data.manifest").load("apps/diskmap/app.xml")
	if launch.isolated and not launch.page then error("--isolated requires --page=<id>", 0) end
	if launch.page and not manifest.pages[launch.page] then
		local ids = {}
		for _, page in ipairs(manifest.order) do table.insert(ids, page.id) end
		error("Unknown Diskmap page: " .. launch.page .. ". Valid pages: " .. table.concat(ids, ", "), 0)
	end
	launch.service = service or Provider.select(arguments)
	return launch
end

return Provider
