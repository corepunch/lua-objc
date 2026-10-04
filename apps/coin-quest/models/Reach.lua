-- Whether an authored level can be cleared: every coin (including coins over
-- water) and the flag are reachable with the verbs the world actually has.
-- Steps, leaps of one cell, pad launches in the arrival direction, ferries
-- along their track, and a key that opens every gate. Saws and spikes are
-- timing, not walls.
local Reach = {}

local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function id(x, z) return x .. ":" .. z end

function Reach.clearable(level)
	local function standable(x, z, opened)
		if level.track[id(x, z)] then return true end
		if not level.ground[id(x, z)] then return false end
		if level.solid[id(x, z)] and not (opened and level.spawns.gates) then
			local gate = false
			for _, g in ipairs(level.spawns.gates or {}) do
				if g.x == x and g.z == z then gate = true end
			end
			if not (opened and gate) then return false end
		end
		return true
	end
	local function blocked(x, z, opened)
		if not level.solid[id(x, z)] then return false end
		if not opened then return true end
		for _, g in ipairs(level.spawns.gates or {}) do
			if g.x == x and g.z == z then return false end
		end
		return true
	end
	local function search(opened)
		local start = level.spawns.player
		local seen, entered, crossed = {[id(start.x, start.z)] = true}, {[id(start.x, start.z)] = {[id(0, 0)] = true}}, {}
		local queue = {{start.x, start.z, 0, 0}}
		local head = 1
		while queue[head] do
			local item = queue[head]
			local x, z, idx, idz = item[1], item[2], item[3], item[4]
			head = head + 1
			local moves = {}
			for _, d in ipairs(DIRS) do
				local dx, dz = d[1], d[2]
				if standable(x + dx, z + dz, opened) then
					table.insert(moves, {x + dx, z + dz, dx, dz, {}})
				end
				local mid = {x + dx, z + dz}
				if not blocked(mid[1], mid[2], opened) and standable(x + 2 * dx, z + 2 * dz, opened) then
					table.insert(moves, {x + 2 * dx, z + 2 * dz, dx, dz, {mid}})
				end
			end
			local span = level:springAt(x, z)
			if span and (idx ~= 0 or idz ~= 0) then
				local mids, ok = {}, true
				for step = 1, span - 1 do
					local cell = {x + step * idx, z + step * idz}
					table.insert(mids, cell)
					if blocked(cell[1], cell[2], opened) then ok = false end
				end
				if ok and standable(x + span * idx, z + span * idz, opened) then
					table.insert(moves, {x + span * idx, z + span * idz, idx, idz, mids})
				end
			end
			for _, move in ipairs(moves) do
				for _, cell in ipairs(move[5]) do crossed[id(cell[1], cell[2])] = true end
				local key = id(move[1], move[2])
				entered[key] = entered[key] or {}
				local dir = id(move[3], move[4])
				if not entered[key][dir] then
					entered[key][dir] = true
					seen[key] = true
					table.insert(queue, {move[1], move[2], move[3], move[4]})
				end
			end
		end
		return seen, crossed
	end
	local locked = search(false)
	local hasKey = #(level.spawns.keys or {}) == 0
	for _, key in ipairs(level.spawns.keys or {}) do hasKey = hasKey or locked[id(key.x, key.z)] end
	local seen, crossed = search(hasKey)
	for _, coin in ipairs(level.spawns.coins) do
		if not seen[id(coin.x, coin.z)] then return false end
	end
	for _, coin in ipairs(level.spawns.aerial or {}) do
		if not crossed[id(coin.x, coin.z)] then return false end
	end
	return seen[id(level.spawns.flag.x, level.spawns.flag.z)] == true
end

return Reach
