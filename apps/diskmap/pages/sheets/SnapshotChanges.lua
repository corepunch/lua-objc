local SheetRoute = require("apps.diskmap.pages.SheetRoute")

-- Every location that changed since the saved snapshot, in a sheet over the
-- window. The comparison itself is services/SnapshotComparison.lua.
local routes = {}

local SnapshotChanges = SheetRoute.extend({view = "sheets/SnapshotChanges", width = 720, height = 520})
routes.snapshotChanges = SnapshotChanges

SnapshotChanges.queries = {rowMenu = true, reveal = true}

function SnapshotChanges:open(parent, result)
	self.result = result
	SheetRoute.open(self, parent)
end

function SnapshotChanges:data()
	return {lists = {changes = self.result.rows}, texts = {title = self.result.title, detail = self.result.detail}}
end

function SnapshotChanges:rowMenu(_, _, row) return row and self:flow("Rows"):resource(row.id) or {} end
function SnapshotChanges:reveal(_, _, row) if row and row.path then self:flow("Rows"):reveal(row.path) end end

return routes
