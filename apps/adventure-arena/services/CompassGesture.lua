local CompassGesture = {}

local DIRECTIONS = {
	"east", "southeast", "south", "southwest",
	"west", "northwest", "north", "northeast",
}

local DRAG = { maximumDistance = 14, rubberBandResistance = 22 }
local SEGMENT = { span = 45 }

function CompassGesture.segments()
	local segments = {}
	for index, direction in ipairs(DIRECTIONS) do
		local center = (index - 1) * SEGMENT.span
		table.insert(segments, {
			direction = direction,
			startAngle = center - SEGMENT.span / 2,
			endAngle = center + SEGMENT.span / 2,
		})
	end
	return segments
end

-- Translations use top-left coordinates on every platform (y grows downward).
function CompassGesture.offset(translation)
	if type(translation) ~= "table" then return 0, 0 end
	local x, y = tonumber(translation.x) or 0, tonumber(translation.y) or 0
	local distance = math.sqrt(x * x + y * y)
	if distance == 0 then return 0, 0 end
	local rubberBandedDistance = DRAG.maximumDistance *
		(1 - math.exp(-distance / DRAG.rubberBandResistance))
	local scale = rubberBandedDistance / distance
	return x * scale, y * scale
end

function CompassGesture.direction(translation)
	if type(translation) ~= "table" then return nil end
	local x, y = tonumber(translation.x) or 0, tonumber(translation.y) or 0
	if math.sqrt(x * x + y * y) < 10 then return nil end
	local degrees = math.deg(math.atan(y, x)) % 360
	local sector = math.floor((degrees + 22.5) / 45) % #DIRECTIONS
	return DIRECTIONS[sector + 1]
end

return CompassGesture
