local Model = require("data.model")
local Provider = {}

-- The service as one window sees it: every function the service calls back
-- later (a measurement's records, a command's output) runs with that window's
-- store bound again (lua/data/model.lua). Confirmations and errors get the
-- window as their parent. Assignments reach the service itself.
function Provider.bind(service, store, promptParent)
	return setmetatable({}, {__index = function(_, key)
		local value = service[key]
		if type(value) ~= "function" then return value end
		return function(...)
			local arguments = table.pack(...)
			if promptParent and (key == "confirmAction" or key == "showError") then
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

-- `--showcase` is the synthetic developer's Mac (services/Fixture.lua), for
-- screenshots and walkthroughs; anything else is this Mac.
function Provider.select(arguments)
	for _, argument in ipairs(arguments or {}) do
		if argument == "--showcase" then return require("apps.diskmap.services.Fixture").new({showcase = true}) end
	end
	return require("apps.diskmap.services.System")
end

-- Process flags, consumed once: `--page=<location>` opens a page
-- (lua/data/location.lua: `--page=xcode`, `--page=/folder//Users/me`),
-- `--folder=<path>` opens the Folder Map on a folder, `--isolated` shows one
-- page without the sidebar.
function Provider.launch(arguments, service)
	local launch = {page = argumentValue(arguments, "--page"), folder = argumentValue(arguments, "--folder")}
	for _, argument in ipairs(arguments or {}) do
		if argument == "--isolated" then launch.isolated = true end
	end
	local manifest = require("data.manifest").load("apps/diskmap/app.xml")
	if launch.isolated and not launch.page then error("--isolated requires --page=<id>", 0) end
	if launch.page and launch.page:sub(1, 1) ~= "/" then launch.page = "/" .. launch.page end
	if launch.page and not manifest.pages[launch.page:match("^/([^/?]*)")] then
		local ids = {}
		for _, page in ipairs(manifest.order) do table.insert(ids, page.id) end
		error("Unknown Diskmap page: " .. launch.page .. ". Valid pages: " .. table.concat(ids, ", "), 0)
	end
	if launch.page then require("data.location").parse(launch.page, manifest.pages) end
	launch.service = service or Provider.select(arguments)
	return launch
end

return Provider
