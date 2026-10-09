-- The breakdown card of every breakdown page (views/pages/Breakdown.etlua):
-- a ring with a legend beside it, or rectangles across the whole card. The
-- page names what it shows above the card; the window's toolbar picks the
-- style for every page at once.
local Breakdown = {
	props = {style = {type = "str", default = "rings"}, explanation = "str",
		total = "str", caption = "str", accessibilityLabel = "str", dragItem = "str", onSelect = "str", onHover = "str", onCenter = "str"},
	records = {
		BreakdownSector = {id = "str", value = "num", color = "str", label = "str", detail = "str"},
		BreakdownRectangle = {id = "str", parent = "str", value = "num", color = "str", label = "str", detail = "str"},
		BreakdownLegend = {id = "str", label = "str", color = "str", sizeText = "str", share = "str", action = "str"},
		BreakdownNote = {title = "str", icon = "str", value = "str", detail = "str"},
	},
}
local BUCKETS = {BreakdownSector = "sectors", BreakdownRectangle = "rectangles", BreakdownLegend = "legend", BreakdownNote = "notes"}
function Breakdown.data(props, records)
	local data = {sectors = {}, rectangles = {}, legend = {}, notes = {}}
	for _, row in ipairs(records) do table.insert(data[BUCKETS[row.tag]], row) end
	return data
end
return Breakdown
