local Scope = {}

-- Totals on different pages describe different populations: a category
-- total, a ranking of locations, a list of files and a count by extension
-- overlap without being the same set. Each page states what its numbers
-- cover beside them, and what the scan could not see.
local POPULATION = {
	largest = "Known locations, each measured once. A file inside a location is also counted by Large Files, so the two are not added together.",
	cleanup = "Estimated recoverable bytes count only what a check proved removable, once per item. Bytes to review are whole-location sizes and overlap Largest Locations.",
	files = "Individual files over 50 MB in the scanned folders. Locations in Largest Locations can contain them.",
	kinds = "Every file by extension at any size, from the same scan; Large Files lists only those over 50 MB.",
}
Scope.pages = POPULATION

-- Coverage of the latest scan as one sentence.
function Scope.coverage(model)
	local scan = model.scan or {}
	local parts = {}
	if scan.running then table.insert(parts, "scan in progress, totals are still growing") end
	if scan.failure and scan.failure ~= "" then table.insert(parts, "the scan stopped early") end
	local protected = scan.protected or 0
	if protected > 0 then table.insert(parts, protected .. (protected == 1 and " protected location" or " protected locations") .. " not readable without Full Disk Access") end
	if not model.includeMedia then table.insert(parts, "Photos, Music and TV libraries excluded") end
	if #parts == 0 then return "Coverage: complete." end
	return "Coverage: " .. table.concat(parts, "; ") .. "."
end

function Scope.text(model, page)
	return (POPULATION[page] or "") .. " " .. Scope.coverage(model)
end

return Scope
