local CompassGesture = {}

local DIRECTIONS = {
	"east", "southeast", "south", "southwest",
	"west", "northwest", "north", "northeast",
}

local DRAG = { maximumDistance = 14, rubberBandResistance = 22 }

function CompassGesture.offset(translation, coordinateSpace)
	if type(translation) ~= "table" then return 0, 0 end
	local x, y = tonumber(translation.x) or 0, tonumber(translation.y) or 0
	if coordinateSpace == "bottom-left" then y = -y end
	local distance = math.sqrt(x * x + y * y)
	if distance == 0 then return 0, 0 end
	local rubberBandedDistance = DRAG.maximumDistance *
		(1 - math.exp(-distance / DRAG.rubberBandResistance))
	local scale = rubberBandedDistance / distance
	return x * scale, y * scale
end

function CompassGesture.direction(translation, coordinateSpace)
	if type(translation) ~= "table" then return nil end
	local x, y = tonumber(translation.x) or 0, tonumber(translation.y) or 0
	if coordinateSpace == "bottom-left" then y = -y end
	if math.sqrt(x * x + y * y) < 10 then return nil end
	local degrees = math.deg(math.atan(y, x)) % 360
	local sector = math.floor((degrees + 22.5) / 45) % #DIRECTIONS
	return DIRECTIONS[sector + 1]
end

return CompassGesture
