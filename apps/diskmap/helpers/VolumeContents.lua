local Format = require("apps.diskmap.helpers.Format")
local VolumeContents = {}

-- What the top level of another disk holds, measured when the person asks.
-- macOS and Windows keep hidden folders at a volume's root; each is named
-- and explained, and its action is the owner's, never a manual delete.
VolumeContents.known = {
	[".Trashes"] = {name = "Trash on this disk", icon = "trash.fill", color = "systemGray", action = "emptyTrash",
		detail = "Items deleted from this disk. Emptying the Trash in Finder empties it too."},
	[".Spotlight-V100"] = {name = "Spotlight index", icon = "magnifyingglass", color = "systemGray", action = "spotlight",
		detail = "Search index for this disk. Add the disk to Spotlight's Privacy list to stop indexing it; macOS then removes the index."},
	[".fseventsd"] = {name = "File change log", icon = "list.bullet.rectangle", color = "systemGray",
		detail = "Records changes for Time Machine and backups. macOS manages its size."},
	[".DocumentRevisions-V100"] = {name = "Document versions", icon = "clock.arrow.circlepath", color = "systemGray",
		detail = "Earlier versions of documents saved on this disk. Manage them from each app's Revert To menu."},
	[".TemporaryItems"] = {name = "Temporary items", icon = "clock", color = "systemGray",
		detail = "Files apps were writing to this disk. They are removed when the disk is ejected cleanly."},
	["$RECYCLE.BIN"] = {name = "Windows Recycle Bin", icon = "trash", color = "systemGray",
		detail = "Files deleted on a Windows PC. Empty the Recycle Bin on that PC."},
	["System Volume Information"] = {name = "Windows system data", icon = "gearshape", color = "systemGray",
		detail = "Restore points and indexing data written by Windows."},
}

-- Rows for a volume's measured top level, largest first. `entries` are the
-- scan's breakdown: {name, kb, directory}.
function VolumeContents.rows(volumePath, entries)
	local rows, total = {}, 0
	for _, entry in ipairs(entries or {}) do
		local bytes = math.floor((entry.kb or 0) * 1024 + 0.5)
		total = total + bytes
		local known = VolumeContents.known[entry.name]
		table.insert(rows, {id = volumePath .. "/" .. entry.name, path = volumePath .. "/" .. entry.name, bytes = bytes, size = Format.size(bytes),
			name = known and known.name or entry.name, subtitle = known and (entry.name .. " · " .. known.detail) or (entry.directory and "Folder" or "File"),
			icon = known and known.icon or (entry.directory and "folder.fill" or "doc.fill"), color = known and known.color or "systemBlue",
			detail = known and "System" or "", system = known ~= nil, action = known and known.action, directory = entry.directory == true})
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	return rows, total
end

return VolumeContents
