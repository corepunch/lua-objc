local Model = require("apps.diskmap.Model")
local Sdks = {}
local NAMES = {
	MacOSX = "macOS", iPhoneOS = "iOS", iPhoneSimulator = "iOS Simulator",
	AppleTVOS = "tvOS", AppleTVSimulator = "tvOS Simulator",
	WatchOS = "watchOS", WatchSimulator = "watchOS Simulator",
	XROS = "visionOS", XRSimulator = "visionOS Simulator", DriverKit = "DriverKit",
}
function Sdks.platform(path)
	local folder = type(path) == "string" and path:match("/([^/]+)%.platform/Developer/SDKs/") or nil
	if folder and NAMES[folder] then return NAMES[folder] end
	if type(path) == "string" and path:find("/CommandLineTools/SDKs/", 1, true) then return "Command Line Tools" end
	return "SDK"
end
function Sdks.discover(service, root)
	local bundles = service.bundles and service.bundles(root, "sdk") or {}
	local rows = {}
	for _, bundle in ipairs(bundles) do
		table.insert(rows, {
			id = bundle.path, name = bundle.name, platform = Sdks.platform(bundle.path), path = bundle.path,
			bytes = bundle.bytes, size = Model.size(bundle.bytes),
		})
	end
	table.sort(rows, function(a, b)
		if (a.bytes or -1) ~= (b.bytes or -1) then return (a.bytes or -1) > (b.bytes or -1) end
		if a.name ~= b.name then return a.name < b.name end
		return a.path < b.path
	end)
	return rows
end
function Sdks.filter(rows, query)
	local needle = (query or ""):lower()
	if needle == "" then return rows end
	local matched = {}
	for _, row in ipairs(rows) do
		if (row.name .. " " .. row.platform .. " " .. row.path):lower():find(needle, 1, true) then table.insert(matched, row) end
	end
	return matched
end
return Sdks
