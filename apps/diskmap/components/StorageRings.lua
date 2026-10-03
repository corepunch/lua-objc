local GEOMETRY = {minimumHole = 0.3, thickness = 0.7 / 3, opacity = {1, 0.72, 0.5}, otherFade = 0.55}
local Rings = {props = {diameter = {type = "num", default = 360}, corner = {type = "num", default = 6}},
	records = {StorageSector = {id = "str", parent = "str", value = "num", color = "str", label = "str", ring = "num", other = "bool"}}}
function Rings.data(props, records)
	local rings, sectors = 1, {}
	for _, record in ipairs(records) do
		local ring = record.ring or 1
		rings = math.max(rings, ring)
		local sector = {}; for key, value in pairs(record) do sector[key] = value end
		sector.ring = ring
		sector.opacity = (GEOMETRY.opacity[ring] or 0.5) * (record.other and record.parent ~= "" and GEOMETRY.otherFade or 1)
		table.insert(sectors, sector)
	end
	return {sectors = sectors, hole = math.max(GEOMETRY.minimumHole, 1 - rings * GEOMETRY.thickness)}
end
return Rings
