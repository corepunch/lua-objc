local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local SystemDetails = require("apps.diskmap.models.SystemDetails")
local Inspector = {}
function Inspector.details(model, id)
	local row = model.resources:find(id); if not row then return nil end
	local m = model.measurements[id]
	local ownerCleanupReady = row.action ~= "ownerCleanup" or (m and m.status == "complete" and (m.bytes or 0) > 0)
	local text = row.consequence or row.subtitle .. ". " .. (row:isLeaf() and "Review this data in its owning app. Size alone does not establish that it is disposable." or "Expand to inspect the measured resources.")
	for _, candidate in ipairs(Cleanup.suggestions(model)) do
		if candidate.id == id then text = candidate.evidence .. "\n\n" .. candidate.subtitle .. "\n\n" .. text; break end
	end
	if id == "system-data" then text = text .. "\n\n" .. SystemDetails.format(SystemDetails.explain(model)) end
	return {name = row.name, text = text, location = (row.path or "Multiple known locations") .. (m and "\n" .. Model.size(m.bytes) .. " · " .. m.status or ""),
		manageTitle = row.action == "simulators" and "Manage simulators…" or row.action == "trash" and "Review Move to Trash…" or row.action == "empty" and "Empty Trash…" or row.action == "ownerCleanup" and "Clear Cache…" or row.action == "settings" and (({siri = "Open Siri Settings", dictation = "Open Dictation Settings", voices = "Open Accessibility Settings"})[row.settingsSection] or "Open System Settings") or row.action == "xcode" and "Open Xcode" or row.action == "docker" and "Open Docker" or "Reveal in Finder",
		canManage = row:isLeaf() and ownerCleanupReady and (row.action ~= "trash" or row:validateTrash()) and (row.action ~= "empty" or row:validateEmpty()) and (row.path ~= nil or row.action == "settings"),
		keepTitle = model.kept[id] and "Stop keeping this resource" or "Keep this resource"}
end
return Inspector
