local SheetPage = require("apps.diskmap.SheetPage")

-- Every location that changed since the saved snapshot, in a sheet over the
-- window. The comparison itself is services/SnapshotComparison.lua.
local SnapshotChanges = SheetPage.define({id = "snapshotChanges", view = "sheets/SnapshotChanges", width = 720, height = 520})

SnapshotChanges.queries = {rowMenu = true, reveal = true}

function SnapshotChanges.new(_, services)
	return setmetatable({services = services}, SnapshotChanges)
end

function SnapshotChanges:open(parent, result)
	self.result = result
	SheetPage.open(self, parent)
end

function SnapshotChanges:data()
	return {lists = {changes = self.result.rows}, texts = {title = self.result.title, detail = self.result.detail}}
end

function SnapshotChanges:rowMenu(_, _, row) return row and self.services.actions:resource(row.id) or {} end
function SnapshotChanges:reveal(_, _, row) if row and row.path then self.services.actions:reveal(row.path) end end

return SnapshotChanges
