local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Preferences = require("apps.diskmap.models.Preferences")
local Inspector = {}
function Inspector.details(model, id, readOnly)
	local row = model.byId[id]; if not row then return nil end
	local m = model.measurements[id]
	local text = row.consequence or row.subtitle .. ". " .. (row.children and "Expand to inspect the measured resources." or "Review this data in its owning app. Size alone does not establish that it is disposable.")
	for _, candidate in ipairs(Cleanup.suggestions(model)) do
		if candidate.id == id then text = candidate.evidence .. "\n\n" .. candidate.subtitle .. "\n\n" .. text; break end
	end
	return {name = row.name, text = text, location = (row.path or "Multiple known locations") .. (m and "\n" .. Model.size(m.bytes) .. " · " .. m.status or ""),
		manageTitle = row.action == "trash" and "Review Move to Trash…" or row.action == "settings" and "Open System Settings" or row.action == "xcode" and "Open Xcode" or row.action == "docker" and "Open Docker" or "Reveal in Finder",
		canManage = not readOnly and not row.children and (row.action ~= "trash" or Preferences.canTrash(model, id)) and (row.path ~= nil or row.action == "settings"),
		canMeasure = not readOnly, keepTitle = model.kept[id] and "Stop keeping this resource" or "Keep this resource"}
end
return Inspector
