local Format = require("apps.diskmap.helpers.Format")
local Simulators = require("apps.diskmap.helpers.Simulators")
local SimulatorPlan = {}

-- "Keep one standard iPhone and one standard iPad": a consolidation plan over
-- every simulator device. The plan only reads rows from Simulators.rows; it
-- never touches a device. Models are told apart by CoreSimulator's device
-- type identifier ("…SimDeviceType.iPhone-17-Pro"), never by the editable
-- device name, which a user can set to anything.

SimulatorPlan.families = {"iPhone", "iPad"}

-- How the page names and colors a device's role in the plan.
local ROLES = {keep = "Keep", remove = "Remove", blocked = "Blocked", preserve = "Protected", undecided = "Choose", outside = "Not in plan"}
local COLORS = {keep = "systemGreen", remove = "systemOrange", blocked = "systemRed", preserve = "systemBlue", undecided = "systemGray", outside = "systemGray"}

-- The family of a device type and whether it is the base model of its line.
-- iPhone-17 and iPad-10th-generation are base models; Pro, Max, Plus, Air,
-- mini, e and SE variants are not. Unknown identifiers belong to no family.
function SimulatorPlan.classify(deviceType)
	if type(deviceType) ~= "string" then return nil, false end
	local body = deviceType:gsub("^com%.apple%.CoreSimulator%.SimDeviceType%.", "")
	if body:match("^iPhone%-%d+$") then return "iPhone", true end
	if body:match("^iPhone%-") then return "iPhone", false end
	if body == "iPad" or body:match("^iPad%-%d+th%-generation$") or body:match("^iPad%-A%d+$") or body:match("^iPad%-%d+$") then
		return "iPad", true
	end
	if body:match("^iPad%-") then return "iPad", false end
	return nil, false
end

-- Installed iOS runtimes that have devices, newest first.
function SimulatorPlan.runtimes(inventory)
	local found = {}
	for _, row in ipairs(Simulators.rows(inventory or {})) do
		local identifier = row.runtimeIdentifier
		local major, minor = tostring(identifier):match("SimRuntime%.iOS%-(%d+)%-(%d+)$")
		if major then found[identifier] = {identifier = identifier, name = row.runtime, order = tonumber(major) * 1000 + tonumber(minor)} end
	end
	local list = {}
	for _, runtime in pairs(found) do table.insert(list, runtime) end
	table.sort(list, function(a, b) if a.order ~= b.order then return a.order > b.order end return a.identifier < b.identifier end)
	return list
end

-- A device is a better keeper when it was used more recently, then holds
-- more data, so the proposal preserves the device with the most to lose.
local function better(a, b)
	local ageA, ageB = a.age or math.huge, b.age or math.huge
	if ageA ~= ageB then return ageA < ageB end
	if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
	return a.id < b.id
end

-- Builds the plan.
--   inventory  what services/Simulators.lua discovered
--   options    runtime     identifier of the chosen iOS runtime (default: newest)
--              keep        {iPhone = udid, iPad = udid} chosen by the user
--              preserve    set of udids the user keeps as specialised QA devices
--              protected   function(udid) -> true when Keep protects the device
-- Every device of the iOS families is in `devices`, tagged with its role:
-- "keep", "preserve" (user or Keep protection), "remove", or "blocked" when
-- the device cannot be removed right now (running, state unknown). Devices of
-- other platforms are listed as "outside". A family with no suitable base
-- model and no user choice is `needsChoice`: none of its devices is proposed.
function SimulatorPlan.build(inventory, options)
	options = options or {}
	local runtimes = SimulatorPlan.runtimes(inventory)
	local runtime = options.runtime
	if not runtime and runtimes[1] then runtime = runtimes[1].identifier end
	local rows = Simulators.rows(inventory or {})
	local byId, familyOf, standard = {}, {}, {}
	for _, row in ipairs(rows) do
		byId[row.id] = row
		familyOf[row.id], standard[row.id] = SimulatorPlan.classify(row.deviceType)
	end
	local plan = {runtime = runtime, runtimes = runtimes, keep = {}, needsChoice = {}, candidates = {}, devices = {}}
	for _, family in ipairs(SimulatorPlan.families) do
		local chosen = options.keep and options.keep[family]
		if chosen and (not byId[chosen] or familyOf[chosen] ~= family or byId[chosen].runtimeIdentifier ~= runtime) then chosen = nil end
		local pool = {}
		for _, row in ipairs(rows) do
			if familyOf[row.id] == family and row.runtimeIdentifier == runtime and row.available ~= false then table.insert(pool, row) end
		end
		table.sort(pool, better)
		plan.candidates[family] = pool
		if not chosen then
			for _, row in ipairs(pool) do
				if standard[row.id] then chosen = row.id; break end
			end
		end
		plan.keep[family] = chosen
		plan.needsChoice[family] = chosen == nil
	end
	local keeping = {}
	for _, id in pairs(plan.keep) do keeping[id] = true end
	local removal, blockedBytes, removalBytes, preservedBytes, keepBytes = {}, 0, 0, 0, 0
	for _, row in ipairs(rows) do
		local family = familyOf[row.id]
		local entry = {id = row.id, name = row.name, runtime = row.runtime, runtimeIdentifier = row.runtimeIdentifier, family = family,
			bytes = row.bytes, size = row.size, lastUse = row.lastUse, state = row.state, running = row.running,
			available = row.available, icon = row.icon, color = row.color, path = row.path, deviceType = row.deviceType, age = row.age}
		if not family then
			entry.role, entry.reason = "outside", "Not an iPhone or iPad, so this plan leaves it alone."
		elseif keeping[row.id] then
			entry.role, entry.reason = "keep", "Kept: the " .. family .. " for " .. row.runtime .. "."
			keepBytes = keepBytes + (row.bytes or 0)
		elseif options.preserve and options.preserve[row.id] then
			entry.role, entry.reason = "preserve", "Preserved as a specialised device."
			preservedBytes = preservedBytes + (row.bytes or 0)
		elseif options.protected and options.protected(row.id) then
			entry.role, entry.reason = "preserve", "Protected by Keep."
			preservedBytes = preservedBytes + (row.bytes or 0)
		elseif plan.needsChoice[family] then
			entry.role, entry.reason = "undecided", "Choose which " .. family .. " to keep before any " .. family .. " is proposed for removal."
		elseif row.running == nil then
			entry.role, entry.reason = "blocked", "Its state could not be checked."
			blockedBytes = blockedBytes + (row.bytes or 0)
		elseif row.running then
			entry.role, entry.reason = "blocked", "Running. Shut it down before deleting."
			blockedBytes = blockedBytes + (row.bytes or 0)
		else
			entry.role = "remove"
			entry.reason = row.runtimeIdentifier == runtime and "Redundant for this minimal setup." or "Redundant: not on the chosen runtime."
			table.insert(removal, entry)
			removalBytes = removalBytes + (row.bytes or 0)
		end
		entry.roleLabel, entry.color = ROLES[entry.role], COLORS[entry.role]
		if row.state == "Booted" or row.running then entry.lastUse = "Running" end
		table.insert(plan.devices, entry)
	end
	-- Rank by what the user can recover first; roles keep their own order.
	local order = {keep = 1, remove = 2, blocked = 3, preserve = 4, undecided = 5, outside = 6}
	table.sort(plan.devices, function(a, b)
		if order[a.role] ~= order[b.role] then return order[a.role] < order[b.role] end
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.id < b.id
	end)
	plan.removal = removal
	plan.removalBytes, plan.blockedBytes, plan.preservedBytes, plan.keepBytes = removalBytes, blockedBytes, preservedBytes, keepBytes
	plan.ready = #removal > 0
	plan.complete = not plan.needsChoice.iPhone and not plan.needsChoice.iPad
	-- The shared runtime is not part of the recovery: the kept devices need it.
	plan.runtimePreserved = runtime
	return plan
end

-- A device may be removed only while it still passes both the plan and the
-- single-device validation (running state, UUID, category Keep). `fresh` is
-- the device's current row, re-read just before the deletion.
function SimulatorPlan.revalidate(plan, id, fresh, kept)
	for _, family in ipairs(SimulatorPlan.families) do
		if plan.keep[family] == id then return false, {code = "kept_device", message = "This device is the kept " .. family .. "."} end
	end
	local planned = false
	for _, entry in ipairs(plan.removal or {}) do if entry.id == id then planned = true end end
	if not planned then return false, {code = "not_in_plan", message = "This device is not in the removal set."} end
	if not fresh then return false, {code = "missing_device", message = "This device no longer exists."} end
	return Simulators.validate("delete", fresh, kept)
end

-- Consequence text for the confirmation: the full removal set, its size and
-- what is lost, in one dialog instead of one per device.
function SimulatorPlan.confirmation(plan)
	local lines = {}
	for _, entry in ipairs(plan.removal) do
		table.insert(lines, entry.name .. " · " .. entry.runtime .. " · " .. entry.size .. " · " .. entry.lastUse)
	end
	local keeps = {}
	for _, family in ipairs(SimulatorPlan.families) do
		local id = plan.keep[family]
		for _, entry in ipairs(plan.devices) do if entry.id == id then table.insert(keeps, entry.name) end end
	end
	return "Delete " .. Format.plural(#plan.removal, "simulator") .. "?\n\n" .. table.concat(lines, "\n")
		.. "\n\nKept: " .. (#keeps > 0 and table.concat(keeps, ", ") or "nothing") .. ". Removes " .. Format.size(plan.removalBytes)
		.. " of installed apps, accounts and data from the deleted devices; the shared runtime stays. This lowers your test coverage and cannot be undone."
end

return SimulatorPlan
