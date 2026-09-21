local Model = {}
local storageColors = {"systemBlue", "systemPurple", "systemOrange"}
function Model.humanKb(kb)
	kb = math.max(0, tonumber(kb) or 0)
	if kb >= 1024 * 1024 then return string.format("%.1f GB", kb / 1024 / 1024) end
	if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
	return string.format("%.0f KB", kb)
end
-- Exact locations only: names like vendor, target, Downloads, or build are not proof of junk.
function Model.rules(home)
	local rules = {
		{"derived", "Xcode Derived Data", "Library/Developer/Xcode/DerivedData", "Rebuildable", "Build products, indexes and logs will be removed. Close Xcode first. The next build and indexing will take longer; source projects remain.", "trash"},
		{"archives", "Xcode Archives", "Library/Developer/Xcode/Archives", "Personal build history", "Archives may contain the only copy of release builds and debug symbols needed for crash reports. Export and back up releases before removing individual archives.", "finder"},
		{"simulators", "Simulator devices", "Library/Developer/CoreSimulator/Devices", "Test data", "Deleting a device erases its installed apps, settings and test data. Review individual devices in Xcode → Window → Devices and Simulators. This size is not a claim that every device is unused.", "xcode"},
		{"runtimes", "Simulator runtimes", "/Library/Developer/CoreSimulator/Images", "Download again", "Use Xcode → Settings → Components to remove runtimes you no longer test. You will need to download them again. Mounted runtimes are excluded from the scan.", "xcode"},
		{"devices", "Xcode device support", "Library/Developer/Xcode/iOS DeviceSupport", "Download again", "Old device support symbols can be recreated when connecting a device. Keep versions you still debug; close Xcode and review individual versions.", "finder"},
		{"backups", "iPhone and iPad backups", "Library/Application Support/MobileSync/Backup", "Backup history", "Deleting a backup removes that restore point. Connect your device in Finder → General → Manage Backups and verify another backup first.", "finder"},
		{"docker", "Docker virtual disk", "Library/Containers/com.docker.docker/Data/vms/0/data", "Contains app data", "This includes images, containers and volumes, which may hold databases. Review Docker Desktop's Images and Containers. Never delete Docker.raw as a cache. Only Docker can identify reclaimable space inside it.", "docker"},
		{"npm", "npm download cache", ".npm/_cacache", "Download again", "Cached package downloads will be removed. Installed projects remain; future installs may need the network. Stop package installations first.", "trash"},
		{"pip", "Python package cache", "Library/Caches/pip", "Download again", "Downloaded packages and cached wheels will be removed. Installed environments remain; future installs may require downloads and rebuilding wheels. Stop pip first.", "trash"},
		{"brew", "Homebrew downloads", "Library/Caches/Homebrew", "Download again", "Cached bottles and downloads will be removed. Installed packages remain; future installs need downloads. Stop Homebrew first.", "trash"},
		{"caches", "Application caches", "Library/Caches", "Review by app", "Caches can include offline content and work in progress. Quit the owning app and use its storage settings where possible. This total overlaps specific cache suggestions and is not added to the reclaimable estimate.", "finder"},
		{"logs", "Application logs", "Library/Logs", "Diagnostic history", "Old logs may help diagnose failures. Quit the owning application and review files by date before removing them.", "finder"},
		{"trash", "Trash", ".Trash", "Deleted personal files", "Emptying Trash permanently removes these files. Review in Finder first. Moving files to Trash does not free their space until Trash is emptied.", "finder"},
	}
	local result = {}
	local automatic = {derived = true, archives = true, simulators = true, runtimes = true, devices = true, npm = true, pip = true, brew = true}
	for _, r in ipairs(rules) do
		result[#result + 1] = {id = r[1], name = r[2], path = r[3]:sub(1, 1) == "/" and r[3] or home .. "/" .. r[3], risk = r[4], consequence = r[5], action = r[6], automatic = automatic[r[1]] == true}
	end
	return result
end
function Model.suggestions(rules, result, checked)
	local rows, reclaimable = {}, 0
	for i, rule in ipairs(rules) do
		local node = result.trees and result.trees[i]
		if type(node) == "table" and (node.kb or 0) > 0 then
			local row = {}
			for key, value in pairs(rule) do row[key] = value end
			row.kb = node.kb; row.size = (node.partial and "≥ " or "") .. Model.humanKb(node.kb)
			row.status = node.partial and "Partial measurement" or rule.risk; row.icon = "lightbulb"
			if node.partial then row.action = "measure" end
			rows[#rows + 1] = row
			if rule.action == "trash" and not node.partial then reclaimable = reclaimable + node.kb end
		elseif checked and not checked[i] then
			local row = {}
			for key, value in pairs(rule) do row[key] = value end
			row.kb = -1; row.size = "Not measured"; row.status = "Check on request"
			row.icon = "lock"; row.action = "measure"
			rows[#rows + 1] = row
		elseif checked and result.rootStates and result.rootStates[i] == "unreadable" then
			local row = {}
			for key, value in pairs(rule) do row[key] = value end
			row.kb = -1; row.size = "Unknown"; row.status = "Access restricted"
			row.icon = "lock"; row.action = "measure"
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b) if a.kb == b.kb then return a.name < b.name end; return a.kb > b.kb end)
	return rows, reclaimable
end
function Model.rows(result, section, query)
	local nodes = {}
	if section == "Large Files" then nodes = result.large or {}
	elseif section == "Applications" then nodes = result.apps or {}
	elseif section == "File Types" then
		for name, info in pairs(result.types or {}) do nodes[#nodes + 1] = {name = name, kb = info.kb, items = info.items, directory = false} end
	else nodes = result.trees and result.trees[1] and result.trees[1].children or {} end
	local rows = {}
	for _, node in ipairs(nodes) do
		local row = {}
		for key, value in pairs(node) do row[key] = value end
		row.size = (node.partial and "≥ " or "") .. Model.humanKb(node.kb)
		row.status = node.partial and "Partial measurement" or node.directory and "Folder" or "File"
		row.icon = node.directory and "folder.fill" or "doc"
		row.iconColor = node.directory and "systemBlue" or "secondary"
		if section == "File Types" then row.status = tostring(node.items) .. " files" end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) if a.kb == b.kb then return a.name < b.name end; return a.kb > b.kb end)
	local root = result.trees and result.trees[1]
	local total = type(root) == "table" and tonumber(root.kb) or 0
	-- Rank before filtering so search preserves the chart colors and denominator.
	local filtered = {}
	for i, row in ipairs(rows) do
		row.shareColor = storageColors[i] or "systemGray"
		if total and total > 0 then
			row.share = math.max(0, math.min(1, (tonumber(row.kb) or 0) / total))
			row.percentage = row.share > 0 and row.share < 0.01 and "<1%" or string.format("%.0f%%", row.share * 100)
		else row.percentage = "—" end
		if not query or row.name:lower():find(query:lower(), 1, true) then filtered[#filtered + 1] = row end
	end
	return filtered
end
function Model.segments(result)
	local root = result.trees and result.trees[1]
	if type(root) ~= "table" or not root.kb or root.kb <= 0 then return {} end
	local rows = Model.rows(result, "Disk Map")
	local segments, used = {}, 0
	local colors = storageColors
	for i = 1, math.min(3, #rows) do
		local row = rows[i]
		if row.kb > 0 then
			segments[#segments + 1] = {name = row.name, size = row.size, weight = row.kb / root.kb, color = colors[i]}
			used = used + row.kb
		end
	end
	if root.kb > used then segments[#segments + 1] = {name = "Other", size = Model.humanKb(root.kb - used), weight = (root.kb - used) / root.kb, color = "systemGray"} end
	return segments
end
function Model.trash(rule, rules, service)
	for _, allowed in ipairs(rules) do
		if rule.id == allowed.id and rule.path == allowed.path and allowed.action == "trash" then
			return service.trash(allowed.path)
		end
	end
	return false, "This location requires manual review."
end
return Model
