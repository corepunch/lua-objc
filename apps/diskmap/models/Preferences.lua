local Preferences = {}
function Preferences.isKept(model, id)
	while id do if model.kept[id] then return true end; id = model.byId[id] and model.byId[id].parentId end
	return false
end
function Preferences.toggle(model, id)
	if not model.byId[id] then return false end
	model.kept[id] = not model.kept[id] or nil
	return true
end
function Preferences.canTrash(model, id)
	local row, m = model.byId[id], model.measurements[id]
	return row and row.action == "trash" and m and m.status == "complete" and (m.bytes or 0) > 0 and not Preferences.isKept(model, id)
end
return Preferences
