local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Developer = {}

-- Developer storage grouped by the decision a developer makes about it. Each
-- section lists catalog groups; their leaves appear as rows and nested groups
-- (a simulator runtime set, one AI tool) roll up into a single row that opens
-- its own list. `roots` lists groups whose direct leaves only are shown.
Developer.sections = {
	{id = "xcode", title = "Xcode & simulators", detail = "Build data, device support and simulators. Runtimes and SDKs are managed by Xcode.", groups = {"xcode"}},
	{id = "packages", title = "Packages & toolchains", detail = "Download caches refill on demand; installed toolchains are removed with their version manager.", groups = {"packages", "toolchains", "test-browsers", "mobile-dev"}},
	{id = "projects", title = "Projects & editors", detail = "Source, generated project folders and editor data. Review before removing anything here.", roots = {"developer"}, groups = {"editors"}},
	{id = "containers", title = "Containers & virtual machines", detail = "Prune from the owning tool. Virtual disks can hold databases and personal work.", groups = {"containers"}},
	{id = "ai", title = "AI tools & models", detail = "Coding-agent caches are separated from sessions and worktrees; model weights download again.", groups = {"ai-tools", "local-models"}},
}

local POLICY = {Rebuildable = "Rebuildable", Essential = "Keep", ["System managed"] = "System managed"}

local function row(model, resource)
	local measured = Categories.row(model, resource.id)
	if not measured then return nil end
	local leaf = resource:isLeaf()
	local value = {id = resource.id, name = resource.name, subtitle = resource.subtitle, icon = resource.icon or "doc",
		color = resource.color or "systemGray", appIcon = resource.appIcon, bytes = measured.bytes or 0, size = measured.size,
		calculating = measured.calculating == true, status = measured.status, group = not leaf,
		detail = model.kept[resource.id] and "Kept" or not leaf and "Group" or POLICY[resource.policy] or "Review"}
	if value.status == "complete" and value.bytes == 0 then return nil end
	if value.status == "notMeasured" or value.status == "excluded" then return nil end
	return value
end

-- Page presentation: sections of rows, largest first, with share bars
-- compared across the whole page so sections can be read against each other.
function Developer.presentation(model, query)
	local needle = (query or ""):lower()
	local sections, largest, total, calculating = {}, 0, 0, false
	for _, section in ipairs(Developer.sections) do
		local rows = {}
		local function add(resource)
			local value = row(model, resource)
			if value and (needle == "" or (value.name .. " " .. (value.subtitle or "") .. " " .. (resource.path or "")):lower():find(needle, 1, true)) then
				table.insert(rows, value)
			end
		end
		for _, id in ipairs(section.roots or {}) do
			local root = model.resources:find(id)
			for _, child in ipairs(root and root:getChildren() or {}) do if child:isLeaf() then add(child) end end
		end
		for _, id in ipairs(section.groups) do
			local group = model.resources:find(id)
			for _, child in ipairs(group and group:getChildren() or {}) do add(child) end
		end
		table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.name < b.name end)
		local bytes = 0
		for _, value in ipairs(rows) do
			bytes = bytes + value.bytes; largest = math.max(largest, value.bytes)
			calculating = calculating or value.calculating
		end
		total = total + bytes
		if #rows > 0 then
			table.insert(sections, {id = section.id, title = section.title, detail = section.detail, rows = rows,
				bytes = bytes, size = Model.size(bytes)})
		end
	end
	for _, section in ipairs(sections) do
		for _, value in ipairs(section.rows) do
			value.relative = largest > 0 and value.bytes / largest or 0
			value.shareText = total > 0 and string.format("%d%%", math.floor(value.bytes * 100 / total + 0.5)) or ""
			if value.shareText == "0%" and value.bytes > 0 then value.shareText = "<1%" end
		end
	end
	local rebuildable = 0
	for _, suggestion in ipairs(Cleanup.suggestions(model)) do
		local resource = model.resources:find(suggestion.id)
		local root = resource
		while root and root:getParent() do root = root:getParent() end
		if root and (root.id == "developer" or root.id == "ai-agents") and suggestion.impact == "Safe/rebuildable" then
			rebuildable = rebuildable + suggestion.bytes
		end
	end
	return {sections = sections, total = Model.size(total), bytes = total, rebuildable = rebuildable,
		rebuildableSize = Model.size(rebuildable), calculating = calculating}
end

return Developer
