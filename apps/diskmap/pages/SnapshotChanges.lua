
-- Every location that changed since the saved snapshot. The comparison
-- itself is services/SnapshotComparison.lua.
local routes = {}

local SnapshotChanges = {view = "pages/SnapshotChanges"}
routes.snapshotChanges = SnapshotChanges

SnapshotChanges.queries = {rowMenu = true, reveal = true}

function SnapshotChanges:data()
	local result = self.app.snapshotResult() or {rows = {}, title = "Snapshot Changes", detail = "No comparison available."}
	local rows = self:flow("Rows"):annotate(result.rows)
	return {lists = {changes = rows}, hidden = {changes = #rows == 0, changesEmpty = #rows > 0}, title = result.title, subtitle = result.detail}
end

function SnapshotChanges:markRow(_, _, row) self:flow("Rows"):toggleReview(row) end

function SnapshotChanges:rowMenu(_, _, row) return row and self:flow("Rows"):resource(row.id) or {} end
function SnapshotChanges:reveal(_, _, row) if row then self.app.open(row.id) end end

function SnapshotChanges:rendered(refs) self.refs = refs end

return routes
