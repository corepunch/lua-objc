local FileKind = require("apps.diskmap.helpers.FileKind")
local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
-- The files the last scan ranked: every file over the size threshold, and
-- the ones unused for a year, each {path, bytes, used}. The store's `files`
-- holds both lists with the extension totals of the same walk.
local Files = Model:extend("files", {primaryKey = "path", source = function(db)
	local files, rows, seen = db.files, {}, {}
	for _, list in ipairs({files and files.large or {}, files and files.old or {}}) do
		for _, file in ipairs(list) do
			if not seen[file.path] then seen[file.path] = true; table.insert(rows, file) end
		end
	end
	return rows
end})

-- One file by its path, read from the two lists without merging them.
function Files:find(path)
	local files = Model.db.files
	for _, list in ipairs({files and files.large or {}, files and files.old or {}}) do
		for _, file in ipairs(list) do
			if file.path == path then return self:load(file) end
		end
	end
end

-- Large Files filters. "Unused" is a year without being opened or changed,
-- the threshold CleanMyMac's Large & Old Files and most Reddit advice use.
-- "Yours" leads: the files a person can act on. Files inside apps, system
-- volumes and tool folders stay under "All", for context.
Files.filters = Model.enum({"Yours", "All", "Unused for a year", "Installers & archives", "Media"})
local FILTER_KINDS = {["Installers & archives"] = {installers = true, archives = true}, Media = {video = true, images = true, audio = true}}

local plural = Format.plural

-- Empty results are a conclusion only after a successful scan. Both file
-- screens share this state so absence of data never becomes a measured zero.
function Files:state()
	local model = Model.db
	local scan, files = model.scan or {}, model.files
	if scan.running then return "loading" end
	if scan.failure and scan.failure ~= "" then return "error", tostring(scan.failure) end
	if not files then return "unavailable", "No file results are available. Refresh to try again." end
	if #files.large == 0 and #files.old == 0 and #files.extensions == 0 then
		if files.partial or (scan.errors or 0) > 0 then return "unavailable", "No file results were readable. Check scan access and refresh." end
		return "empty"
	end
	return "loaded"
end

-- A home-relative folder, so rows read like Finder's path bar.
function Files:folder(path)
	local model = Model.db
	local folder = path:match("^(.*)/[^/]+$") or path
	if model.home and (folder == model.home or folder:sub(1, #model.home + 1) == model.home .. "/") then
		return "~" .. folder:sub(#model.home + 1)
	end
	return folder
end

-- Individual files may be moved to the Trash only when they are ordinary
-- documents in the home folder: never inside ~/Library, a hidden folder or a
-- package, never below a kept, essential or system-managed location, and only
-- when the latest scan measured them.
function Files:validateTrash(path)
	local model = Model.db
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("/%.%.?/") or path:find("\0", 1, true) then
		return false, {code = "invalid_path", message = "This is not an absolute file path."}
	end
	local home = model.home or ""
	if home == "" or path:sub(1, #home + 1) ~= home .. "/" then
		return false, {code = "outside_home", message = "Only files in your home folder can be moved to the Trash here."}
	end
	local relative = path:sub(#home + 2)
	if relative:match("^Library/") then
		return false, {code = "library", message = "Files in Library belong to apps. Review their category instead."}
	end
	for component in relative:gmatch("[^/]+") do
		if component:sub(1, 1) == "." then
			return false, {code = "hidden", message = "Files in hidden folders belong to tools. Review them with the owning tool."}
		end
	end
	for component in (relative:match("^(.*)/[^/]+$") or ""):gmatch("[^/]+") do
		local extension = component:match("%.([^.]+)$")
		if extension and FileKind.packages[extension:lower()] then
			return false, {code = "package", message = "This file is inside " .. component .. ". Manage it in the app that owns it."}
		end
	end
	local owner = Locations:owner(path)
	if owner then
		if owner:isKept() then return false, {code = "kept", message = owner.name .. " is marked Keep."} end
		-- Inside generated project output the unit of decision is the artifact (and
		-- its project), not one index or binary in it.
		if owner.artifact then
			return false, {code = "artifact", message = "This file is part of " .. owner.name .. ". Review the project's build output, not single files."}
		end
		if owner.policy == "Essential" or owner.policy == "System managed" then
			return false, {code = "protected", message = owner.name .. " is managed by its owner."}
		end
	end
	if not self:find(path) then return false, {code = "not_measured", message = "Refresh Diskmap to measure this file again first."} end
	return true
end

local function matches(row, needle)
	return needle == "" or (row.name .. " " .. row.path .. " " .. row.owner):lower():find(needle, 1, true) ~= nil
end

-- Rows for Large Files. `kind` narrows to one File Types kind. Share bars
-- compare files with the largest one shown.
function Files:rows(filter, query, kind, now)
	local model = Model.db
	local summary = model.files
	if not summary then return {} end
	now = now or os.time()
	local source = filter == "Unused for a year" and summary.old or summary.large
	local kinds, needle = FILTER_KINDS[filter], (query or ""):lower()
	local oldBefore = now - require("apps.diskmap.models.Scans").fileSummary.oldDays * 86400
	local rows = {}
	for _, file in ipairs(source) do
		local fileKind = FileKind.of(file.path)
		if (not kinds or kinds[fileKind.id]) and (not kind or fileKind.id == kind) then
			local owner = Locations:owner(file.path)
			local row = {id = file.path, path = file.path, name = file.path:match("([^/]+)$") or file.path,
				subtitle = (owner and owner.path ~= file.path and owner.path ~= file.path:match("^(.*)/[^/]+$") and (owner.name .. " · ") or "") .. Files:folder(file.path), bytes = file.bytes, size = Format.size(file.bytes),
				owner = owner and owner.name or "", ownerId = owner and owner.id or nil,
				lastUse = Format.age(file.used, now), used = file.used, old = (file.used or now) < oldBefore,
				kind = fileKind.name, kindId = fileKind.id, fileIcon = file.path, icon = fileKind.icon, color = fileKind.color,
				trashable = (Files:validateTrash(file.path))}
			row.detail = Format.used(row.lastUse)
			-- "Yours" and "Installers & archives" list only what this app would move
			-- to the Trash. System and runtime images share the extension but
			-- not the owner: they stay under All and in the File Types totals.
			local removableOnly = filter == "Yours" or filter == "Installers & archives"
			if matches(row, needle) and (not removableOnly or row.trashable) then table.insert(rows, row) end
		end
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.path < b.path end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and row.bytes / largest or 0
		row.shareText = ""
	end
	return rows
end

-- File Types: extension totals grouped into kinds, largest first, each with
-- its unused share and the extensions that make it up.
function Files:kinds()
	local model = Model.db
	local summary = model.files
	if not summary then return {}, {} end
	local byKind, extensions = {}, {}
	for _, row in ipairs(summary.extensions) do
		local kind = row.extension ~= "" and FileKind.byExtension[row.extension] or FileKind.other
		local total = byKind[kind.id] or {kind = kind, bytes = 0, count = 0, oldBytes = 0, extensions = {}}
		total.bytes, total.count, total.oldBytes = total.bytes + row.bytes, total.count + row.count, total.oldBytes + (row.oldBytes or 0)
		table.insert(total.extensions, row)
		byKind[kind.id] = total
		table.insert(extensions, row)
	end
	local rows, all = {}, 0
	for _, total in pairs(byKind) do all = all + total.bytes end
	-- The installers kind counts every disk image by extension, system and
	-- runtime images included. What this app would move to the Trash is the
	-- user-owned subset, stated beside the inventory total, never as it.
	local removable = {}
	for _, file in ipairs(Files:rows("Installers & archives")) do
		local entry = removable[file.kindId] or {count = 0, bytes = 0}
		entry.count, entry.bytes = entry.count + 1, entry.bytes + file.bytes
		removable[file.kindId] = entry
	end
	for _, total in pairs(byKind) do
		table.sort(total.extensions, function(a, b) return a.bytes > b.bytes end)
		local top = {}
		for index = 1, math.min(3, #total.extensions) do
			local extension = total.extensions[index].extension
			if extension ~= "" then table.insert(top, "." .. extension) end
		end
		local own = FILTER_KINDS["Installers & archives"][total.kind.id] and (removable[total.kind.id] or {count = 0, bytes = 0}) or nil
		table.insert(rows, {id = total.kind.id, name = total.kind.name, icon = total.kind.icon, color = total.kind.color,
			advice = total.kind.advice, bytes = total.bytes, size = Format.size(total.bytes), count = total.count, oldBytes = total.oldBytes,
			subtitle = table.concat(top, ", ") .. (#top > 0 and total.oldBytes > 0 and " · " or "")
				.. (total.oldBytes > 0 and (Format.size(total.oldBytes) .. " unused for a year") or "")
				.. (own and ((#top > 0 or total.oldBytes > 0) and " · " or "")
					.. "total stored · " .. (own.count > 0 and (Format.size(own.bytes) .. " in " .. plural(own.count, "file") .. " yours to review")
						or "none of it yours to review") or ""),
			removableBytes = own and own.bytes or nil, removableCount = own and own.count or nil,
			share = all > 0 and total.bytes / all or 0})
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.id < b.id end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and row.bytes / largest or 0
		row.shareText = Format.percent(row.bytes, all)
	end
	table.sort(extensions, function(a, b) return a.bytes > b.bytes end)
	local top = {}
	for _, row in ipairs(extensions) do
		if row.extension ~= "" then
			local kind = FileKind.byExtension[row.extension] or FileKind.other
			-- The Files column carries the count; the subtitle names the kind.
			table.insert(top, {id = row.extension, name = "." .. row.extension, subtitle = kind.name,
				icon = kind.icon, color = kind.color, bytes = row.bytes, size = Format.size(row.bytes), count = row.count, kindId = kind.id,
				relative = extensions[1].bytes > 0 and row.bytes / extensions[1].bytes or 0,
				shareText = Format.percent(row.bytes, all)})
			if #top >= 12 then break end
		end
	end
	return rows, top
end

-- One-line summary of the latest file ranking for page headers and the
-- recommendations page.
function Files:summary(now)
	local model = Model.db
	local summary = model.files
	if not summary then return nil end
	local count, bytes = #summary.large, 0
	for _, file in ipairs(summary.large) do bytes = bytes + file.bytes end
	local old, oldBytes = 0, 0
	for _, file in ipairs(summary.old) do
		if Files:validateTrash(file.path) then old = old + 1; oldBytes = oldBytes + file.bytes end
	end
	return {count = count, bytes = bytes, oldBytes = summary.oldBytes, oldCount = summary.oldCount,
		reviewableOld = old, reviewableOldBytes = oldBytes, partial = summary.partial}
end

return Files
