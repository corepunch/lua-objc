local Model = require("apps.diskmap.Model")
local Kinds = require("apps.diskmap.knowledge.FileKinds")
local Files = {}

-- Large Files filters. "Unused" is a year without being opened or changed,
-- the threshold CleanMyMac's Large & Old Files and most Reddit advice use.
Files.filters = {"All", "Unused for a year", "Installers & archives", "Media"}
local FILTER_KINDS = {["Installers & archives"] = {installers = true, archives = true}, Media = {video = true, images = true, audio = true}}

-- Folders that are documents to Finder. A file inside one belongs to its app
-- (a Photos library, an Xcode archive, a virtual machine), so Diskmap never
-- offers to trash it on its own.
local PACKAGES = {"app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
	"logicx", "band", "xcarchive", "bundle", "framework", "lrdata", "sparsebundle", "pvm", "utm", "vmwarevm",
	"aplibrary", "migratedphotolibrary", "xcodeproj", "xcworkspace", "playground", "rtfd", "pages", "numbers", "key"}
local packageSet = {}
for _, extension in ipairs(PACKAGES) do packageSet[extension] = true end

local kindByExtension = {}
for _, kind in ipairs(Kinds) do
	for _, extension in ipairs(kind.extensions) do kindByExtension[extension] = kind end
end
local OTHER = Kinds[#Kinds]

function Files.kind(path)
	local extension = (path or ""):match("[^/]%.([^./]+)$")
	return extension and kindByExtension[extension:lower()] or OTHER
end
function Files.kindById(id)
	for _, kind in ipairs(Kinds) do if kind.id == id then return kind end end
end

local function plural(count, word) return count .. " " .. word .. (tostring(count) == "1" and "" or "s") end

-- "3 days ago", "5 months ago", "2 years ago": the precision a person needs
-- to decide whether a file is still in use.
function Files.age(seconds, now)
	if not seconds or seconds <= 0 then return "Unknown" end
	local days = math.floor(((now or os.time()) - seconds) / 86400)
	if days < 1 then return "Today" end
	if days < 2 then return "Yesterday" end
	if days < 31 then return days .. " days ago" end
	if days < 365 then return plural(math.floor(days / 30.4), "month") .. " ago" end
	return plural(math.floor(days / 365), "year") .. " ago"
end

-- A home-relative folder, so rows read like Finder's path bar.
function Files.folder(model, path)
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
function Files.validateTrash(model, path)
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
		if extension and packageSet[extension:lower()] then
			return false, {code = "package", message = "This file is inside " .. component .. ". Manage it in the app that owns it."}
		end
	end
	local owner = model.resources:owner(path)
	if owner then
		if owner:isKept() then return false, {code = "kept", message = owner.name .. " is marked Keep."} end
		if owner.policy == "Essential" or owner.policy == "System managed" then
			return false, {code = "protected", message = owner.name .. " is managed by its owner."}
		end
	end
	local measured = false
	for _, file in ipairs(model.files and model.files.large or {}) do if file.path == path then measured = true; break end end
	if not measured then for _, file in ipairs(model.files and model.files.old or {}) do if file.path == path then measured = true; break end end end
	if not measured then return false, {code = "not_measured", message = "Refresh Diskmap to measure this file again first."} end
	return true
end

local function matches(row, needle)
	return needle == "" or (row.name .. " " .. row.path .. " " .. row.owner):lower():find(needle, 1, true) ~= nil
end

-- Rows for Large Files. `kind` narrows to one File Types kind. Share bars
-- compare files with the largest one shown.
function Files.rows(model, filter, query, kind, now)
	local summary = model.files
	if not summary then return {} end
	now = now or os.time()
	local source = filter == "Unused for a year" and summary.old or summary.large
	local kinds, needle = FILTER_KINDS[filter], (query or ""):lower()
	local oldBefore = now - require("apps.diskmap.models.Inventory").summary.oldDays * 86400
	local rows = {}
	for _, file in ipairs(source) do
		local fileKind = Files.kind(file.path)
		if (not kinds or kinds[fileKind.id]) and (not kind or fileKind.id == kind) then
			local owner = model.resources:owner(file.path)
			local row = {id = file.path, path = file.path, name = file.path:match("([^/]+)$") or file.path,
				subtitle = (owner and owner.path ~= file.path and owner.path ~= file.path:match("^(.*)/[^/]+$") and (owner.name .. " · ") or "") .. Files.folder(model, file.path), bytes = file.bytes, size = Model.size(file.bytes),
				owner = owner and owner.name or "", ownerId = owner and owner.id or nil,
				lastUse = Files.age(file.used, now), used = file.used, old = (file.used or now) < oldBefore,
				kind = fileKind.name, kindId = fileKind.id, fileIcon = file.path, icon = fileKind.icon, color = fileKind.color,
				trashable = (Files.validateTrash(model, file.path))}
			row.detail = row.lastUse
			if matches(row, needle) then table.insert(rows, row) end
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
function Files.kinds(model)
	local summary = model.files
	if not summary then return {}, {} end
	local byKind, extensions = {}, {}
	for _, row in ipairs(summary.extensions) do
		local kind = row.extension ~= "" and kindByExtension[row.extension] or OTHER
		local total = byKind[kind.id] or {kind = kind, bytes = 0, count = 0, oldBytes = 0, extensions = {}}
		total.bytes, total.count, total.oldBytes = total.bytes + row.bytes, total.count + row.count, total.oldBytes + (row.oldBytes or 0)
		table.insert(total.extensions, row)
		byKind[kind.id] = total
		table.insert(extensions, row)
	end
	local rows, all = {}, 0
	for _, total in pairs(byKind) do all = all + total.bytes end
	for _, total in pairs(byKind) do
		table.sort(total.extensions, function(a, b) return a.bytes > b.bytes end)
		local top = {}
		for index = 1, math.min(3, #total.extensions) do
			local extension = total.extensions[index].extension
			if extension ~= "" then table.insert(top, "." .. extension) end
		end
		table.insert(rows, {id = total.kind.id, name = total.kind.name, icon = total.kind.icon, color = total.kind.color,
			advice = total.kind.advice, bytes = total.bytes, size = Model.size(total.bytes), count = total.count, oldBytes = total.oldBytes,
			subtitle = plural(Model.count(total.count), "file") .. (#top > 0 and (" · " .. table.concat(top, ", ")) or "")
				.. (total.oldBytes > 0 and (" · " .. Model.size(total.oldBytes) .. " unused for a year") or ""),
			share = all > 0 and total.bytes / all or 0})
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.id < b.id end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and row.bytes / largest or 0
		local percent = all > 0 and row.bytes * 100 / all or 0
		row.shareText = percent > 0 and percent < 1 and "<1%" or string.format("%d%%", math.floor(percent + 0.5))
	end
	table.sort(extensions, function(a, b) return a.bytes > b.bytes end)
	local top = {}
	for _, row in ipairs(extensions) do
		if row.extension ~= "" then
			local kind = kindByExtension[row.extension] or OTHER
			table.insert(top, {id = row.extension, name = "." .. row.extension, subtitle = kind.name .. " · " .. plural(Model.count(row.count), "file"),
				icon = kind.icon, color = kind.color, bytes = row.bytes, size = Model.size(row.bytes), kindId = kind.id,
				relative = extensions[1].bytes > 0 and row.bytes / extensions[1].bytes or 0,
				shareText = all > 0 and string.format("%.1f%%", row.bytes * 100 / all) or ""})
			if #top >= 12 then break end
		end
	end
	return rows, top
end

-- One-line summary of the latest file ranking for page headers and the
-- recommendations page.
function Files.summary(model, now)
	local summary = model.files
	if not summary then return nil end
	local count, bytes = #summary.large, 0
	for _, file in ipairs(summary.large) do bytes = bytes + file.bytes end
	local old, oldBytes = 0, 0
	for _, file in ipairs(summary.old) do
		if Files.validateTrash(model, file.path) then old = old + 1; oldBytes = oldBytes + file.bytes end
	end
	return {count = count, bytes = bytes, oldBytes = summary.oldBytes, oldCount = summary.oldCount,
		reviewableOld = old, reviewableOldBytes = oldBytes, partial = summary.partial}
end

return Files
