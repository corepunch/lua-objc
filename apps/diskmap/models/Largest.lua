local Model = require("apps.diskmap.Model")
local Overview = require("apps.diskmap.models.Overview")
local Scope = require("apps.diskmap.models.Scope")
local Largest = {}

-- The ranking stops where individual items stop mattering at a glance; the
-- category lists still show everything.
Largest.limit = 100

-- The Largest Items page a PageController presents.
Largest.page = {id = "largest", layout = {summaryId = "largestSummary", scopeNote = Scope.pages.largest,
	sections = {{list = {id = "largest", menu = "rowMenu", activate = "open", status = true}}},
	footnote = {text = "Known locations measured individually, across every category. Open an item's menu to show it in Finder, review it, or keep it out of suggestions."},
}, present = function(model, state)
	local rows = Overview.largest(model, state.disk, Largest.limit, state.query)
	local bytes = 0
	for _, row in ipairs(rows) do bytes = bytes + row.bytes end
	local disk = state.disk
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	return {lists = {largest = rows}, texts = {scopeNote = Scope.text(model, "largest"), largestSummary = #rows == 0 and "No measured items match yet."
		or string.format("The %d largest measured locations use %s%s.", #rows, Model.size(bytes),
			used and used >= bytes and (" of " .. Model.size(used) .. " used") or "")}}
end}

return Largest
