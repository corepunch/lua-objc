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

-- What a page's numbers cover, then `coverage`, what the latest scan saw
-- (Scans:coverage()).
function Scope.text(page, coverage)
	return (POPULATION[page] or "") .. " " .. coverage
end

return Scope
