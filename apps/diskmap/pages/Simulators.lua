local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local Simulators = require("apps.diskmap.helpers.Simulators")
local SimulatorService = require("apps.diskmap.services.Simulators")
local SimulatorPlan = require("apps.diskmap.helpers.SimulatorPlan")
local Selection = require("apps.diskmap.helpers.Selection")
local Outcome = require("apps.diskmap.helpers.Outcome")
local Batch = require("apps.diskmap.helpers.Batch")

-- The Simulators page: devices from CoreSimulator's folders, runtimes from
-- `simctl runtime list`, and the minimal device set (helpers/SimulatorPlan.lua)
-- that leads the page. The page outlives a visit: the root reads the
-- inventory when a scan finishes, before or without the page, and a read that
-- ends later asks the app to draw again with `app.refresh()`.
local Page = {view = "pages/Simulators"}
-- What only reads; every other action changes what the page shows.
Page.queries = {reveal = true, components = true}

local FAMILY_IDS = {iPhone = "Phone", iPad = "Pad"}

function Page:init()
	self.service = self.app.service
	self.inventory, self.filterIndex, self.keep = {}, 1, {}
end

-- The page is read again whenever it opens, like a request.
function Page:activate() self:load() end

-- The plan for the inventory and the choices made so far. Its totals are also
-- published for Clean Up: the same removal set the page offers, so the two
-- screens cannot disagree about eligibility or recoverable bytes.
function Page:plan()
	local plan = SimulatorPlan.build(self.inventory, {runtime = self.chosenRuntime, keep = self.keep,
		protected = function(udid)
			local catalog = Locations:find("simulators")
			return (catalog and catalog:isKept()) or Locations.keeps(Simulators.keepKey(udid))
		end})
	Model.db.simulatorPlan = self.loaded and {removalBytes = plan.removalBytes, removalCount = #plan.removal,
		blockedBytes = plan.blockedBytes, complete = plan.complete, runtime = plan.runtime} or nil
	return plan
end

-- The row of `rows` that stands for `row`, which an earlier read produced.
local function pick(rows, row)
	for _, candidate in ipairs(rows) do if row and candidate.id == row.id then return candidate end end
end

-- A family's Picker: the ids it offers (false is "Choose…"), their labels and
-- the position of the kept one.
local function choices(plan, family)
	local ids, labels, index = {}, {}, 0
	if plan.needsChoice[family] and #plan.candidates[family] > 0 then
		table.insert(ids, false); table.insert(labels, "Choose…")
	end
	for _, row in ipairs(plan.candidates[family]) do
		table.insert(ids, row.id); table.insert(labels, row.name .. " · " .. row.size)
		if row.id == plan.keep[family] then index = #labels - 1 end
	end
	return ids, labels, index
end

-- The plan as one decision: a headline naming what is kept and what goes, and
-- the details that qualify it. Recoverable bytes sit beside the review button.
local function planText(self, plan)
	local keeps = {}
	for _, family in ipairs(SimulatorPlan.families) do
		for _, entry in ipairs(plan.devices) do if entry.id == plan.keep[family] then table.insert(keeps, entry.name) end end
	end
	local headline = (#keeps > 0 and ("Keep " .. table.concat(keeps, " and ")) or "Choose the devices to keep")
		.. (#plan.removal > 0 and ("; delete " .. Format.plural(#plan.removal, "redundant device") .. ".") or "; no other device is eligible to delete.")
	local parts = {}
	if plan.blockedBytes > 0 then table.insert(parts, Format.size(plan.blockedBytes) .. " more is blocked until running devices shut down or can be checked.") end
	if plan.preservedBytes > 0 then table.insert(parts, Format.size(plan.preservedBytes) .. " is protected by Keep.") end
	if plan.runtimePreserved then table.insert(parts, "The shared runtime stays for the kept devices and is not counted.") end
	if #parts == 0 then table.insert(parts, "Each device is checked again just before it is deleted.") end
	return headline, table.concat(parts, " ")
end

local function planView(self, plan)
	local runtimeIndex, families = 0, {}
	for index, runtime in ipairs(plan.runtimes) do if runtime.identifier == plan.runtime then runtimeIndex = index - 1 end end
	for _, family in ipairs(SimulatorPlan.families) do
		local _, labels, index = choices(plan, family)
		table.insert(families, {id = FAMILY_IDS[family], title = family, options = labels, index = index,
			note = plan.needsChoice[family] and ("No standard " .. family .. " is available; choose which one to keep.") or ""})
	end
	local headline, summary = planText(self, plan)
	local removable = #plan.removal
	local row = self.planSelected
	return {runtimes = plan.runtimes, runtimeIndex = runtimeIndex, families = families, headline = headline, summary = summary,
		amount = Format.size(plan.removalBytes),
		reviewTitle = removable > 0 and ("Review " .. Format.plural(removable, "Device") .. "…") or "Review…",
		preserveTitle = row and Locations.keeps(Simulators.keepKey(row.id)) and "Remove Keep" or "Keep Device",
		status = self.planResult or ""}
end

-- The header's totals and the explanation of the device list.
local function texts(self, runtimes)
	local summary = Simulators.summary(self.inventory, runtimes)
	local runtimeSummary = self.runtimeList and (Format.size(summary.runtimeBytes) .. " in " .. Format.plural(summary.runtimes, "runtime"))
		or "runtime storage could not be measured"
	local detail = {"Erase keeps a device and removes its apps and data; Delete removes the device."}
	if summary.stale > 0 then table.insert(detail, Format.plural(summary.stale, "device") .. " unused for " .. Simulators.staleDays .. " days.") end
	if summary.unknownAvailability > 0 then table.insert(detail, Format.plural(summary.unknownAvailability, "device") .. " could not be checked for availability.")
	elseif summary.unavailable > 0 then table.insert(detail, Format.plural(summary.unavailable, "device") .. " unavailable, " .. Format.size(summary.unavailableBytes) .. " of apps and data.") end
	return self.error or ((self.busy and "Refreshing · " or "") .. Format.size(summary.deviceBytes) .. " stored in "
		.. Format.plural(summary.devices, "device") .. " · " .. runtimeSummary), table.concat(detail, " ")
end

function Page:data(state)
	-- Nothing is known until the first read ends: a zero would read as a measurement.
	if not self.loaded and not self.error then
		self.lists = {}
		return {computing = "Reading simulator devices and runtimes…", disabled = {retry = true}}
	end
	local inventory, query = self.inventory, state.query or ""
	local rows = Simulators.rows(inventory, query, Simulators.filters[self.filterIndex])
	local allRuntimes = Simulators.runtimeRows(self.runtimeList, inventory)
	local runtimes = query == "" and allRuntimes or Simulators.runtimeRows(self.runtimeList, inventory, query)
	local plan = self:plan()
	self.selected, self.selectedRuntime = pick(rows, self.selected), pick(runtimes, self.selectedRuntime)
	self.planSelected = pick(plan.devices, self.planSelected)
	self.lists = {devices = rows, runtimes = runtimes, planDevices = #plan.runtimes > 0 and plan.devices or nil}
	local selected, runtime, allowed = self.selected, self.selectedRuntime, not self.busy
	local _, deviceReason = Simulators.validate("delete", selected, Locations.keeps)
	local _, runtimeReason = Simulators.validateRuntime(runtime, Locations.keeps)
	local status = self.deviceError or (#rows == 0 and "No matching devices." or Format.plural(#rows, "device"))
	if selected then status = deviceReason and deviceReason.message or (selected.name .. " · " .. selected.state) end
	local summary, detail = texts(self, allRuntimes)
	local row = self.planSelected
	return {
		filters = Simulators.filters, filter = self.filterIndex - 1, summary = summary, devicesDetail = detail, status = status,
		runtimeStatus = runtime and runtimeReason and runtimeReason.message or self.runtimeError or "",
		plan = planView(self, plan),
		lists = self.lists,
		hidden = {runtimesSection = self.runtimeList ~= nil and #allRuntimes == 0},
		disabled = {
			erase = not (allowed and Simulators.command("erase", selected, Locations.keeps)),
			delete = not (allowed and Simulators.command("delete", selected, Locations.keeps)),
			reveal = not (allowed and selected and type(selected.path) == "string"),
			deleteUnavailable = not (allowed and #self:unavailableDevices() > 0),
			deleteRuntime = not (allowed and Simulators.runtimeCommand(runtime, Locations.keeps)),
			retry = not allowed,
			planReview = not (allowed and plan.ready),
			planPreserve = not (allowed and row and row.family),
			planKeepThis = not (allowed and row and row.family and row.runtimeIdentifier == plan.runtime
				and row.available ~= false and plan.keep[row.family] ~= row.id),
		},
	}
end

-- After a draw the native selections follow the chosen rows.
function Page:rendered(refs)
	local selected = {devices = self.selected, runtimes = self.selectedRuntime, planDevices = self.planSelected}
	for id, rows in pairs(self.lists) do Selection.show(refs[id], rows, selected[id] and selected[id].id) end
end

function Page:filter(index) self.filterIndex = (index or 0) + 1 end
function Page:select(_, _, row) self.selected = row end
function Page:selectRuntime(_, _, row) self.selectedRuntime = row end
function Page:planSelect(_, _, row) self.planSelected = row end
function Page:retry() self:load() end

function Page:reveal()
	if self.selected and self.selected.path then self.service.reveal(self.selected.path) end
end

function Page:components()
	local ok, message = self.service.openOwner("xcode")
	if ok == false then self.service.showError("Cannot open Xcode", message) end
end

function Page:planRuntime(index)
	local runtime = self:plan().runtimes[(index or 0) + 1]
	if runtime then self.chosenRuntime, self.keep, self.planResult = runtime.identifier, {}, nil end
end

function Page:chooseKeep(family, index)
	self.keep[family] = (choices(self:plan(), family))[(index or 0) + 1] or nil
	self.planResult = nil
end
function Page:planPhone(index) self:chooseKeep("iPhone", index) end
function Page:planPad(index) self:chooseKeep("iPad", index) end

function Page:planKeepThis()
	local row = self.planSelected
	if not row or not row.family then return end
	self.keep[row.family], self.planResult = row.id, nil
end

-- Keep for one device persists with the other Keep choices.
function Page:planPreserve()
	local row = self.planSelected
	if not row or not row.family then return end
	Locations:toggleKeep(Simulators.keepKey(row.id))
	if self.service.saveKeep then self.service.saveKeep(Model.db.kept) end
	self.planResult = nil
end

-- A read belongs to the inventory, not to one visit of the page: it may start
-- before the page opens and end after it was left. Coming back shows what was
-- read last time while it is read again; only the first visit has nothing.
function Page:load()
	if self.busy then return end
	self.busy = true
	self.error, self.deviceError, self.runtimeError = nil, nil, nil
	if not self.loaded then self.inventory = {} end
	local service, runtimeList, inventory, pending = self.service, nil, nil, 2
	local function done()
		pending = pending - 1
		if pending > 0 then return end
		self.busy, self.runtimeList = false, runtimeList
		if type(inventory) == "table" and type(inventory.devices) == "table" then self.inventory, self.loaded = inventory, true
		else self.error = "Simulator folders could not be read." end
		self:plan()
		self.app.refresh()
	end
	if type(service.simulatorRuntimes) == "function" then
		service.simulatorRuntimes(function(value, error) runtimeList, self.runtimeError = value, error; done() end)
	else done() end
	local function discover(listed, error)
		self.deviceError = error
		local ok, discovered = pcall(SimulatorService.discover, service, Model.db.home, listed)
		if not ok then done(); return end
		inventory = discovered
		local paths, slots = {}, {}
		for _, devices in pairs(discovered.devices or {}) do
			for _, device in ipairs(devices) do
				if device.dataPathSize == nil and device.measurePath then
					table.insert(paths, device.measurePath); table.insert(slots, device)
				end
			end
		end
		if #paths == 0 or type(service.measure) ~= "function" then done(); return end
		service.measure(paths, function(sizes)
			for index, device in ipairs(slots) do device.dataPathSize = sizes[index] end
			done()
		end)
	end
	if type(service.simulatorDevices) == "function" then service.simulatorDevices(discover) else discover() end
end

-- Runs validated commands one at a time, revalidating each target first.
function Page:run(commands, targets, validate)
	self.busy = true
	local function step(index)
		if index > #commands then
			self.busy = false
			self:load()
			return
		end
		if not validate(targets[index]) then self.busy = false; self.app.refresh(); return end
		self.service.command(commands[index], function(ok, output)
			self.app.log(table.concat(commands[index], " ", 3), ok, targets[index].bytes, targets[index].name or targets[index].id, not ok and output or nil)
			if not ok then
				self.busy, self.error = false, "Action failed: " .. tostring(output):sub(1, 220)
				self.app.refresh()
				return
			end
			self.app.removed(targets[index].path, targets[index].bytes)
			step(index + 1)
		end)
	end
	step(1)
	return true
end

-- The unavailable devices that may be deleted now.
function Page:unavailableDevices()
	local rows = {}
	for _, row in ipairs(Simulators.rows(self.inventory, nil, "Unavailable")) do
		if Simulators.command("delete", row, Locations.keeps) then table.insert(rows, row) end
	end
	return rows
end

function Page:perform(action, targets, many)
	if self.busy or #targets == 0 then return false end
	local commands, names = {}, {}
	for _, row in ipairs(targets) do
		local command = Simulators.command(action, row, Locations.keeps)
		if not command then return false end
		table.insert(commands, command); table.insert(names, row.name .. " · " .. row.id)
	end
	local title = many and "Delete unavailable simulators" or action == "erase" and "Erase simulator contents" or "Delete simulator device"
	local message = many and (table.concat(names, "\n") .. "\n\nThese devices cannot use their current runtime. Their apps and data may still be valuable. Permanently deletes ONLY these devices and their contents. Installed runtimes are preserved. This cannot be undone.")
		or Simulators.impact(action, targets[1])
	if not self.service.confirmAction(title, message) then return false end
	return self:run(commands, targets, function(row) return Simulators.validate(action, row, Locations.keeps) end)
end

function Page:erase() return self:perform("erase", {self.selected}) end
function Page:delete() return self:perform("delete", {self.selected}) end
function Page:unavailable() return self:perform("delete", self:unavailableDevices(), true) end

function Page:deleteRuntime()
	local row = self.selectedRuntime
	if self.busy or not Simulators.runtimeCommand(row, Locations.keeps) then return false end
	if not self.service.confirmAction("Delete simulator runtime", Simulators.runtimeImpact(row)) then return false end
	return self:run({Simulators.runtimeCommand(row, Locations.keeps)}, {row}, function(target) return Simulators.validateRuntime(target, Locations.keeps) end)
end

-- The shared review flow: one confirmation for the whole removal set, then
-- each device is re-read from CoreSimulator and revalidated before its own
-- deletion. A refused or failed device is reported and the rest continue.
function Page:planReview()
	if self.busy then return false end
	local plan = self:plan()
	if not plan.ready then return false end
	if not self.service.confirmAction("Delete redundant simulators", SimulatorPlan.confirmation(plan)) then return false end
	self.busy, self.planResult = true, "Deleting…"
	local freeBefore = Outcome.free(self.service, Model.db.home)
	Batch.run(plan.removal, {
		label = function(entry) return entry.name end,
		bytes = function(entry) return entry.bytes end,
		refresh = function(entry, done)
			if type(self.service.simulatorState) ~= "function" then done(entry); return end
			self.service.simulatorState(entry.id, function(record)
				if not record then done(nil); return end
				local state, running = record.state, nil
				if state == "Shutdown" then running = false
				elseif state == "Booted" or state == "Booting" or state == "Shutting Down" then running = true end
				done({id = entry.id, name = entry.name, runtime = entry.runtime, available = record.isAvailable, running = running})
			end)
		end,
		validate = function(entry, fresh) return SimulatorPlan.revalidate(plan, entry.id, fresh, Locations.keeps) end,
		execute = function(entry, done)
			self.service.command({"/usr/bin/xcrun", "simctl", "delete", entry.id}, function(success, output)
				self.app.log("simctl delete " .. entry.id, success, entry.bytes, entry.name, not success and output or nil)
				if success then self.app.removed(entry.path, entry.bytes) end
				done(success, output)
			end)
		end,
	}, function(result)
		-- The result is kept whether or not the page is open: the next visit
		-- shows it, and the inventory is read again either way.
		self.busy, self.planResult = false, Batch.report(result, "Deleted", "device")
			.. ". Kept devices and the shared runtime were not touched; simulators are deleted at once, not moved to the Trash. "
			.. Outcome.freeText(freeBefore, Outcome.free(self.service, Model.db.home), result.removed > 0) .. "."
		self:load()
	end)
	return true
end

return {simulators = Page}
