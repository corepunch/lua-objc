local Model = require("apps.diskmap.Model")
local Duplicates = {}

-- Groups of files with identical contents, from the duplicate search in the
-- folders the person chose. Each group keeps one copy; the others are what a
-- cleanup would remove, and their private bytes (APFS clones share blocks)
-- are what it would free.

local TRANSIENT = {"/Downloads/", "/Desktop/"}

local function transient(path)
	for _, part in ipairs(TRANSIENT) do if path:find(part, 1, true) then return true end end
	return false
end

-- The copy to keep: one outside Downloads and Desktop, then the shortest
-- path, then the first alphabetically.
function Duplicates.keeper(group)
	local best
	for _, file in ipairs(group.files) do
		if not best then best = file
		else
			local a, b = transient(file.path), transient(best.path)
			if a ~= b then
				if not a then best = file end
			elseif #file.path ~= #best.path then
				if #file.path < #best.path then best = file end
			elseif file.path < best.path then
				best = file
			end
		end
	end
	return best
end

-- The files a cleanup would remove from a group, as basket items.
function Duplicates.copies(group)
	local keep, items = Duplicates.keeper(group), {}
	for _, file in ipairs(group.files) do
		if file ~= keep then
			table.insert(items, {path = file.path, name = file.path:match("([^/]+)$"), bytes = file.privateBytes, source = "Duplicates",
				consequence = "An identical copy of " .. keep.path .. ", which stays. Only blocks this copy does not share are freed."})
		end
	end
	return items, keep
end

local function folder(path, home)
	local directory = path:match("^(.*)/[^/]+$") or path
	if home and directory:sub(1, #home) == home then directory = "~" .. directory:sub(#home + 1) end
	return directory
end

function Duplicates.rows(groups, query, home)
	local rows, needle = {}, (query or ""):lower()
	for _, group in ipairs(groups or {}) do
		local first = group.files[1].path
		local name = first:match("([^/]+)$") or first
		local _, keep = Duplicates.copies(group)
		if needle == "" or name:lower():find(needle, 1, true) then
			table.insert(rows, {id = first, path = keep.path, name = name, group = group, bytes = group.reclaimable or 0,
				size = Model.size(group.reclaimable or 0), detail = #group.files .. " copies",
				subtitle = Model.size(group.bytes) .. " each · keeps " .. folder(keep.path, home),
				icon = "doc.on.doc.fill", color = "systemTeal"})
		end
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	return rows
end

-- Which empty state the page is in, so "nothing chosen yet" is never read as
-- "nothing found": choose (no folder), ready (folders chosen, not searched),
-- failed, none (searched, no duplicates), nomatch (the filter hides every
-- group) or list. A running search is not a state of its own: the page is
-- computing.
function Duplicates.state(roots, result, shown, query)
	if result and (result.failure or result.groups == nil) then return "failed" end
	if #(roots or {}) == 0 then return "choose" end
	if not result then return "ready" end
	if shown > 0 then return "list" end
	if #result.groups == 0 then return "none" end
	return (query or "") ~= "" and "nomatch" or "none"
end

function Duplicates.summary(groups)
	local copies, bytes = 0, 0
	for _, group in ipairs(groups or {}) do
		copies = copies + #group.files - 1
		bytes = bytes + (group.reclaimable or 0)
	end
	return {groups = #(groups or {}), copies = copies, bytes = bytes}
end

return Duplicates
