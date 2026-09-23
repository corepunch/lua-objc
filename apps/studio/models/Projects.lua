local Projects = {}

Projects.defaultIcon = "app.dashed"

local function safeName(value)
	return type(value) == "string" and value:match("^[%w_%-]+$") ~= nil
end

function Projects.list(read, decode, encode, write)
	local source = read("projects.json")
	local names = {}
	if source then
		local ok, values = pcall(decode, source)
		if ok and type(values) == "table" then names = values end
	end
	if #names == 0 then
		names = { "StarterApp", "HabitTracker" }
		write("projects.json", encode(names))
	end
	local result = {}
	for _, name in ipairs(names) do
		if safeName(name) then
			local metaSource = read(name .. "/project.lua")
			local metadata = { name = name, bundleId = "org.example." .. name:lower(), appIcon = Projects.defaultIcon }
			if metaSource then
				local chunk = load(metaSource, "@project.lua", "t", {})
				if chunk then
					local ok, value = pcall(chunk)
					if ok and type(value) == "table" then
						for key, field in pairs(value) do if type(field) == "string" then metadata[key] = field end end
					end
				end
			end
			metadata.id = name
			metadata.appIcon = metadata.appIcon ~= "" and metadata.appIcon or Projects.defaultIcon
			metadata.title = metadata.name
			metadata.icon = metadata.appIcon
			metadata.selected = #result == 0
			result[#result + 1] = metadata
		end
	end
	return result
end

function Projects.save(write, name, metadata)
	if not safeName(name) or type(metadata) ~= "table" then return nil, "Invalid project" end
	for _, key in ipairs({ "name", "bundleId", "appIcon" }) do
		if type(metadata[key]) ~= "string" then return nil, "Invalid " .. key end
	end
	local bundleId = metadata.bundleId
	if not bundleId:match("^[%w_%-%.]+$") or not bundleId:find("%.", 1, false) or bundleId:match("%.%.") or bundleId:match("^%.") or bundleId:match("%.$") then
		return nil, "Enter a valid bundle identifier"
	end
	if metadata.appIcon == "" then metadata.appIcon = Projects.defaultIcon end
	local content = "return {\n\tname = " .. string.format("%q", metadata.name) .. ",\n\tbundleId = " .. string.format("%q", metadata.bundleId) .. ",\n\tappIcon = " .. string.format("%q", metadata.appIcon) .. ",\n}\n"
	return write(name .. "/project.lua", content)
end

return Projects
