local Format = require("apps.diskmap.helpers.Format")
local Sdks = require("apps.diskmap.helpers.Sdks")
local Discovery = {}

function Discovery.discover(service, root)
	local bundles = service.bundles(root, "sdk")
	local rows = {}
	for _, bundle in ipairs(bundles) do
		table.insert(rows, {
			id = bundle.path, name = bundle.name, platform = Sdks.platform(bundle.path), path = bundle.path,
			bytes = bundle.bytes, size = Format.size(bundle.bytes),
		})
	end
	table.sort(rows, function(a, b)
		if (a.bytes or -1) ~= (b.bytes or -1) then return (a.bytes or -1) > (b.bytes or -1) end
		if a.name ~= b.name then return a.name < b.name end
		return a.path < b.path
	end)
	return rows
end

return Discovery
