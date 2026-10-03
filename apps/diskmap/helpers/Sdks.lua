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
