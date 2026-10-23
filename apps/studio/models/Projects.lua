local Projects = {}

Projects.defaultIcon = "app.fill"
Projects.defaultProjectIcon = "rocket-sketch"
Projects.iconChoices = {
	{ id = "rocket-sketch", title = "Rocket Sketch", symbol = "pencil.tip.crop.circle", file = "rocket-sketch.png" },
	{ id = "desk", title = "Studio Desk", symbol = "pencil.and.ruler", file = "desk.png" },
	{ id = "rocket", title = "Lua-objc Rocket", symbol = "paperplane.fill", file = "rocket.png" },
}

-- What a new project starts from. `root` is the bundled folder the files
-- are read from; the files keep the demo/playground module namespace every
-- project runs in.
Projects.templates = {
	{ id = "blank", title = "Blank App", icon = "app.dashed", appIcon = "app.fill",
		caption = "A counter on one screen: the smallest Model, Controller and view.",
		root = "demo/playground/", files = { "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" } },
	{ id = "habits", title = "Habit Tracker", icon = "checklist", appIcon = "checklist",
		caption = "Three tabs with local storage: Today, Stats and Settings.",
		root = "apps/studio/Documents/HabitTracker/", files = { "init.lua", "Model.lua", "Controller.lua",
			"views/Window.etlua", "views/Today.etlua", "views/Stats.etlua", "views/Settings.etlua" } },
}

function Projects.template(id)
	for _, template in ipairs(Projects.templates) do
		if template.id == id then return template end
	end
	return nil
end

--- The template's files, relative path to content, read with `read`.
function Projects.templateFiles(template, read)
	local files = {}
	for _, path in ipairs(template.files) do
		local content = read(template.root .. path)
		if not content then return nil, "Template file is missing: " .. template.root .. path end
		files[path] = content
	end
	return files
end

--- The folder a project named `name` lives in: its letters and digits,
--- unique among `existing` ids. Nil and a message when nothing usable is left.
function Projects.folderName(name, existing)
	if type(name) ~= "string" then return nil, "Enter a project name" end
	local folder = name:gsub("[^%w]", "")
	if folder == "" then return nil, "Enter a project name with letters or digits" end
	local taken = {}
	for _, project in ipairs(existing or {}) do taken[(project.id or project):lower()] = true end
	if taken[folder:lower()] then return nil, "A project called " .. folder .. " already exists" end
	return folder
end

--- A bundle identifier for a project folder.
function Projects.bundleId(folder)
	return "org.example." .. folder:lower()
end

function Projects.iconChoice(id)
	for _, choice in ipairs(Projects.iconChoices) do
		if choice.id == id then return choice end
	end
	return nil
end

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
		names = { "HabitTracker", "StarterApp" }
		write("projects.json", encode(names))
	end
	local result = {}
	for _, name in ipairs(names) do
		if safeName(name) then
			local metaSource = read(name .. "/project.lua")
			local metadata = { name = name, bundleId = "org.example." .. name:lower(),
				appIcon = Projects.defaultIcon, projectIcon = Projects.defaultProjectIcon }
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
			if not Projects.iconChoice(metadata.projectIcon) then metadata.projectIcon = Projects.defaultProjectIcon end
			metadata.title = metadata.name
			metadata.icon = metadata.appIcon
			metadata.selected = #result == 0
			table.insert(result, metadata)
		end
	end
	-- Studio opens the populated Habit Tracker workspace on a fresh launch,
	-- even when an earlier build persisted StarterApp first in the menu.
	for index, project in ipairs(result) do
		if project.id == "HabitTracker" then
			if index > 1 then table.insert(result, 1, table.remove(result, index)) end
			break
		end
	end
	for index, project in ipairs(result) do project.selected = index == 1 end
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
	if not Projects.iconChoice(metadata.projectIcon) then metadata.projectIcon = Projects.defaultProjectIcon end
	local content = "return {\n\tname = " .. string.format("%q", metadata.name) .. ",\n\tbundleId = " .. string.format("%q", metadata.bundleId) .. ",\n\tappIcon = " .. string.format("%q", metadata.appIcon) .. ",\n\tprojectIcon = " .. string.format("%q", metadata.projectIcon) .. ",\n}\n"
	return write(name .. "/project.lua", content)
end

return Projects
