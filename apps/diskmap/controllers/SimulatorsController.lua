local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Simulators = require("apps.diskmap.models.Simulators")
local SimulatorPlan = require("apps.diskmap.models.SimulatorPlan")
local Controller = Page.extend("simulators", "Simulators")

-- The Simulators page: devices from CoreSimulator's folders and runtimes from
-- `simctl runtime list`. `changed` asks the root to remeasure after an action.
function Controller.new(model, service, changed)
	return setmetatable({model = model, service = service, changed = changed,
		inventory = {}, runtimes = {}, runtimeList = nil, query = "", filterIndex = 1}, Controller)
end

function Controller:mount(host, state)
	self.query, self.filterIndex, self.selected, self.selectedRuntime = state.query or "", 1, nil, nil
	self.planRuntime, self.planKeep, self.planSelected, self.planChildren, self.planResult = nil, {}, nil, nil, nil
	local refs = self:attach(host, {filters = Simulators.filters, actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:show() end,
		select = function(_, _, row) self.selected = row; self:buttons() end,
		selectRuntime = function(_, _, row) self.selectedRuntime = row; self:buttons() end,
		reveal = function() if self.selected and self.selected.path then self.service.reveal(self.selected.path) end end,
		erase = function() self:perform("erase") end,
		delete = function() self:perform("delete") end,
		unavailable = function() self:perform("delete", true) end,
		deleteRuntime = function() self:deleteRuntime() end,
		components = function() self.service.openOwner("xcode") end,
		retry = function() self:load() end,
	}})
	self:load()
	return refs
end

function Controller:filter() return Simulators.filters[self.filterIndex] end

function Controller:buttons()
	local refs = self.refs
	if not refs then return end
	local allowed = not self.busy
	refs.erase.enabled = allowed and Simulators.command("erase", self.selected, self.model) ~= nil
	refs.delete.enabled = allowed and Simulators.command("delete", self.selected, self.model) ~= nil
	refs.reveal.enabled = allowed and self.selected ~= nil and type(self.selected.path) == "string"
	local unavailable = 0
	for _, row in ipairs(Simulators.rows(self.inventory, nil, "Unavailable")) do
		if Simulators.command("delete", row, self.model) then unavailable = unavailable + 1 end
	end
	refs.unavailableTileAction.enabled = allowed and unavailable > 0
	refs.deleteRuntime.enabled = allowed and Simulators.runtimeCommand(self.selectedRuntime, self.model) ~= nil
	local _, deviceReason = Simulators.validate("delete", self.selected, self.model)
	if self.selected then refs.status.text = deviceReason and deviceReason.message or (self.selected.name .. " · " .. self.selected.state) end
	refs.retry.enabled = allowed
	self:planButtons()
	local _, reason = Simulators.validateRuntime(self.selectedRuntime, self.model)
	refs.runtimeStatus.text = self.selectedRuntime and reason and reason.message or self.runtimeError or ""
end

-- Presents the loaded inventory without reloading it: filters and search
-- change what is shown, never what is measured.
function Controller:show()
	local refs = self.refs
	if not refs then return end
	local rows = Simulators.rows(self.inventory, self.query, self:filter())
	refs.devices:replaceRows(rows)
	self.runtimes = Simulators.runtimeRows(self.runtimeList, self.inventory, self.query)
	refs.runtimes:replaceRows(self.runtimes)
	refs.runtimesSection.hidden = self.runtimeList ~= nil and #Simulators.runtimeRows(self.runtimeList, self.inventory) == 0
	local summary = Simulators.summary(self.inventory, Simulators.runtimeRows(self.runtimeList, self.inventory))
	if self.loading then
		-- Nothing is known yet: a zero here would read as a measurement.
		for _, tile in ipairs({"devicesTile", "runtimesTile", "unavailableTile"}) do
			refs[tile .. "Value"].text = "—"
			refs[tile .. "Detail"].text = "Reading…"
		end
		refs.summary.text = "Reading simulator devices and runtimes…"
	else
		refs.devicesTileValue.text = Model.size(summary.deviceBytes)
		refs.devicesTileDetail.text = Model.plural(summary.devices, "device")
			.. (summary.stale > 0 and (" · " .. summary.stale .. " unused for " .. Simulators.staleDays .. " days") or "")
		refs.runtimesTileValue.text = self.runtimeList and Model.size(summary.runtimeBytes) or "Not measured"
		refs.runtimesTileDetail.text = self.runtimeList and (Model.plural(summary.runtimes, "runtime") .. " installed")
			or "Xcode's command-line tools could not list runtimes"
		refs.unavailableTileValue.text = summary.unknownAvailability > 0 and summary.unavailable == 0 and "Unknown" or tostring(summary.unavailable)
		refs.unavailableTileDetail.text = summary.unknownAvailability > 0 and (Model.plural(summary.unknownAvailability, "device") .. " could not be checked")
			or summary.unavailable == 0 and "No devices reported unavailable"
			or (Model.size(summary.unavailableBytes) .. " of apps and data on devices whose runtime is gone")
		local runtimeSummary = self.runtimeList and (Model.size(summary.runtimeBytes) .. " in " .. Model.plural(summary.runtimes, "runtime"))
			or "Runtime storage could not be measured"
		refs.summary.text = self.error or ((self.busy and "Refreshing · " or "")
			.. Model.size(summary.deviceBytes) .. " in " .. Model.plural(summary.devices, "device") .. " · " .. runtimeSummary)
	end
	refs.status.text = self.deviceError or (self.loading and "" or #rows == 0 and "No matching devices." or Model.plural(#rows, "device"))
	refs.runtimeStatus.text = self.runtimeError or ""
	if self.busy then refs.devices:showLoading() else refs.devices:hideLoading() end
	self.selected, self.selectedRuntime = nil, nil
	self:buttons()
	self:showPlan()
end

-- The minimal device set: built from the inventory by models/SimulatorPlan.lua
-- and presented by its own template, so the page above reconciles untouched.
local FAMILY_TITLES = {iPhone = {id = "Phone", title = "iPhone"}, iPad = {id = "Pad", title = "iPad"}}
function Controller:buildPlan()
	return SimulatorPlan.build(self.inventory, {runtime = self.planRuntime, keep = self.planKeep,
		protected = function(udid)
			local catalog = self.model.resources:find("simulators")
			return (catalog and catalog:isKept()) or Simulators.isKept(self.model, udid)
		end})
end

local ROLES = {keep = "Keep", remove = "Remove", blocked = "Blocked", preserve = "Protected", undecided = "Choose", outside = "Not in plan"}
local COLORS = {keep = "systemGreen", remove = "systemOrange", blocked = "systemRed", preserve = "systemBlue", undecided = "systemGray", outside = "systemGray"}

function Controller:planSummary(plan)
	if self.loading then return "Reading simulator devices…" end
	local keeps = {}
	for _, family in ipairs(SimulatorPlan.families) do
		for _, entry in ipairs(plan.devices) do if entry.id == plan.keep[family] then table.insert(keeps, entry.name) end end
	end
	local parts = {#keeps > 0 and ("Keeps " .. table.concat(keeps, " and ")) or "Nothing is kept yet"}
	if #plan.removal > 0 then
		table.insert(parts, "removes " .. Model.plural(#plan.removal, "device") .. ", " .. Model.size(plan.removalBytes) .. " of apps and data")
	else
		table.insert(parts, "no device is eligible for removal")
	end
	if plan.blockedBytes > 0 then table.insert(parts, Model.size(plan.blockedBytes) .. " blocked until shut down or checked") end
	if plan.preservedBytes > 0 then table.insert(parts, Model.size(plan.preservedBytes) .. " protected by Keep") end
	local text = table.concat(parts, " · ") .. "."
	if plan.runtimePreserved then text = text .. " The shared runtime stays for the kept devices and is not part of this total." end
	return text
end

function Controller:showPlan()
	if not self.template or not self.refs or not self.refs.planHost then return end
	local plan = self:buildPlan()
	self.plan = plan
	self:publishPlan()
	self.planChildren = self.planChildren or self.template:child("planHost", "apps/diskmap/views/SimulatorPlan.etlua")
	local runtimeIndex, families, options = 0, {}, {}
	for index, runtime in ipairs(plan.runtimes) do if runtime.identifier == plan.runtime then runtimeIndex = index - 1 end end
	for _, family in ipairs(SimulatorPlan.families) do
		local list, labels, index = {}, {}, 0
		if plan.needsChoice[family] and #plan.candidates[family] > 0 then
			table.insert(labels, "Choose…"); table.insert(list, false)
		end
		for position, row in ipairs(plan.candidates[family]) do
			table.insert(labels, row.name .. " · " .. row.size); table.insert(list, row.id)
			if row.id == plan.keep[family] then index = #labels - 1 end
		end
		options[family] = list
		table.insert(families, {id = FAMILY_TITLES[family].id, title = FAMILY_TITLES[family].title, options = labels, index = index,
			note = plan.needsChoice[family] and ("No standard " .. family .. " is available; choose which one to keep.") or ""})
	end
	self.planOptions = options
	local rows = {}
	for _, entry in ipairs(plan.devices) do
		local row = {}
		for key, value in pairs(entry) do row[key] = value end
		row.roleLabel, row.color = ROLES[entry.role], COLORS[entry.role]
		row.lastUse = (entry.state == "Booted" or entry.running) and "Running" or entry.lastUse
		table.insert(rows, row)
	end
	local selected = self.planSelected and self.planSelected.id
	local removable = #plan.removal
	local data = {runtimes = plan.runtimes, runtimeIndex = runtimeIndex, families = families, summary = self:planSummary(plan),
		reviewTitle = removable > 0 and ("Review and Delete " .. Model.plural(removable, "Device") .. "…") or "Review and Delete…",
		preserveTitle = selected and Simulators.isKept(self.model, selected) and "Remove Keep" or "Keep Device",
		status = self.planResult or "", actions = {
			planRuntime = function(index) self.planRuntime = plan.runtimes[(index or 0) + 1].identifier; self.planKeep = {}; self:showPlan() end,
			planPhone = function(index) self:chooseKeep("iPhone", index) end,
			planPad = function(index) self:chooseKeep("iPad", index) end,
			planSelect = function(_, _, row) self.planSelected = row; self:planButtons() end,
			planPreserve = function() self:togglePreserve() end,
			planKeepThis = function() self:keepSelected() end,
			planReview = function() self:reviewPlan() end,
		}}
	local _, refs = self.planChildren:update(data)
	self.planRefs = refs
	if refs and refs.planDevices then refs.planDevices:replaceRows(rows) end
	self.planSelected = nil
	self:planButtons()
end

function Controller:planButtons()
	local refs, plan = self.planRefs, self.plan
	if not refs or not refs.planReview then return end
	refs.planReview.enabled = not self.busy and not self.loading and plan ~= nil and plan.ready
	local row = self.planSelected
	refs.planPreserve.enabled = not self.busy and row ~= nil and row.family ~= nil
	refs.planKeepThis.enabled = not self.busy and row ~= nil and row.family ~= nil and row.runtimeIdentifier == plan.runtime
		and row.available ~= false and plan.keep[row.family] ~= row.id
end

function Controller:chooseKeep(family, index)
	local id = self.planOptions and self.planOptions[family] and self.planOptions[family][(index or 0) + 1]
	self.planKeep[family] = id or nil
	self.planResult = nil
	self:showPlan()
end

function Controller:keepSelected()
	local row = self.planSelected
	if not row or not row.family then return end
	self.planKeep[row.family] = row.id
	self.planResult = nil
	self:showPlan()
end

-- Keep for one device persists with the other Keep choices.
function Controller:togglePreserve()
	local row = self.planSelected
	if not row or not row.family then return end
	Simulators.toggleKept(self.model, row.id)
	if self.service.saveKeep then self.service.saveKeep(self.model.kept) end
	self.planResult = nil
	self:showPlan()
end

-- The shared review flow: one confirmation for the whole removal set, then
-- each device is re-read from CoreSimulator and revalidated before its own
-- deletion. A refused or failed device is reported and the rest continue.
function Controller:reviewPlan()
	if self.busy then return false end
	local plan = self:buildPlan()
	if not plan.ready then return false end
	if not self.service.confirmAction("Delete redundant simulators", SimulatorPlan.confirmation(plan)) then return false end
	self.busy = true; self.planResult = "Deleting…"
	self:show()
	local generation = self.generation
	local deleted, deletedBytes, skipped, failed = 0, 0, {}, {}
	local function finish()
		local parts = {}
		if deleted > 0 then table.insert(parts, "Deleted " .. Model.plural(deleted, "device") .. " (" .. Model.size(deletedBytes) .. ")") end
		if #skipped > 0 then table.insert(parts, "Skipped " .. table.concat(skipped, "; ")) end
		if #failed > 0 then table.insert(parts, "Failed " .. table.concat(failed, "; ")) end
		if #parts == 0 then parts[1] = "Nothing was deleted" end
		self.changed()
		if generation == self.generation then
			self.busy, self.planResult = false, table.concat(parts, ". ") .. ". Kept devices and the shared runtime were not touched; free space updates with the next scan."
			self:load()
		end
	end
	local function step(index)
		local entry = plan.removal[index]
		if not entry then finish(); return end
		local function proceed(fresh)
			local ok, reason = SimulatorPlan.revalidate(plan, entry.id, fresh, self.model)
			if not ok then
				table.insert(skipped, entry.name .. " (" .. reason.message .. ")")
				step(index + 1); return
			end
			self.service.command({"/usr/bin/xcrun", "simctl", "delete", entry.id}, function(success, output)
				if self.log then self.log("simctl delete " .. entry.id, success, entry.bytes, entry.name, not success and output or nil) end
				if success then deleted = deleted + 1; deletedBytes = deletedBytes + (entry.bytes or 0)
				else table.insert(failed, entry.name .. " (" .. tostring(output):sub(1, 80) .. ")") end
				step(index + 1)
			end)
		end
		if type(self.service.simulatorState) ~= "function" then proceed(entry); return end
		self.service.simulatorState(entry.id, function(record)
			if not record then proceed(nil); return end
			local state, running = record.state, nil
			if state == "Shutdown" then running = false
			elseif state == "Booted" or state == "Booting" or state == "Shutting Down" then running = true end
			proceed({id = entry.id, name = entry.name, runtime = entry.runtime, available = record.isAvailable, running = running})
		end)
	end
	step(1)
	return true
end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

function Controller:finish(generation, inventory, runtimeList)
	if generation ~= self.generation then return end
	self.busy, self.loading = false, false
	if type(inventory) == "table" and type(inventory.devices) == "table" then self.inventory = inventory; self.loaded = true
	else self.error = "Simulator folders could not be read." end
	self.runtimeList = runtimeList
	self:publishPlan()
	self:show()
	if self.published then self.published() end
end

-- The plan's totals, for Clean Up: the same removal set the page offers, so
-- the two screens cannot disagree about eligibility or recoverable bytes.
function Controller:publishPlan()
	if not self.loaded then self.model.simulatorPlan = nil; return end
	local plan = self:buildPlan()
	self.model.simulatorPlan = {removalBytes = plan.removalBytes, removalCount = #plan.removal, blockedBytes = plan.blockedBytes,
		complete = plan.complete, runtime = plan.runtime}
end

function Controller:load()
	if self.busy then return end
	-- Coming back to the page shows what was read last time while it is
	-- read again; only the first visit has nothing to show.
	self.busy, self.loading = true, not self.loaded
	self.error, self.deviceError, self.runtimeError = nil, nil, nil
	if not self.loaded then self.inventory = {} end
	self:show()
	local generation = self.generation
	local runtimeList, inventory, pending = nil, nil, 2
	local function done()
		pending = pending - 1
		if pending == 0 then self:finish(generation, inventory, runtimeList) end
	end
	if type(self.service.simulatorRuntimes) == "function" then
		self.service.simulatorRuntimes(function(value, error)
			if generation ~= self.generation then return end
			runtimeList, self.runtimeError = value, error; done()
		end)
	else done() end
	local function discover(listed, error)
		if generation ~= self.generation then return end
		self.deviceError = error
		local ok, discovered = pcall(Simulators.discover, self.service, self.model.home, listed)
		if not ok then done(); return end
		inventory = discovered
		local paths, slots = {}, {}
		for _, devices in pairs(discovered.devices or {}) do
			for _, device in ipairs(devices) do
				if device.dataPathSize == nil and device.measurePath then
					table.insert(paths, device.measurePath)
					table.insert(slots, device)
				end
			end
		end
		if #paths == 0 or type(self.service.measure) ~= "function" then done(); return end
		self.service.measure(paths, function(sizes)
			if generation ~= self.generation then return end
			for index, device in ipairs(slots) do device.dataPathSize = sizes[index] end
			done()
		end)
	end
	if type(self.service.simulatorDevices) == "function" then self.service.simulatorDevices(discover)
	else discover() end
end

-- Runs validated commands one at a time, revalidating each target first.
function Controller:run(commands, targets, validate)
	self.busy = true; self:show()
	local generation = self.generation
	local function step(index)
		if index > #commands then
			self.changed()
			if generation == self.generation then self.busy = false; self:load() end
			return
		end
		if not validate(targets[index]) then
			if generation == self.generation then self.busy = false; self:show() end
			return
		end
		self.service.command(commands[index], function(ok, output)
			if self.log then self.log(table.concat(commands[index], " ", 3), ok, targets[index].bytes, targets[index].name or targets[index].id, not ok and output or nil) end
			if not ok then
				self.changed()
				if generation == self.generation then
					self.busy = false; self.error = "Action failed: " .. tostring(output):sub(1, 220); self:show()
				end
				return
			end
			step(index + 1)
		end)
	end
	step(1)
	return true
end

function Controller:perform(action, unavailable)
	if self.busy then return false end
	local targets = unavailable and Simulators.rows(self.inventory, nil, "Unavailable") or {self.selected}
	local commands, names = {}, {}
	for _, row in ipairs(targets) do
		local command = Simulators.command(action, row, self.model)
		if not command then return false end
		table.insert(commands, command); table.insert(names, row.name .. " · " .. row.id)
	end
	if #commands == 0 then return false end
	local title = unavailable and "Delete unavailable simulators" or action == "erase" and "Erase simulator contents" or "Delete simulator device"
	local message = unavailable and (table.concat(names, "\n") .. "\n\nThese devices cannot use their current runtime. Their apps and data may still be valuable. Permanently deletes ONLY these devices and their contents. Installed runtimes are preserved. This cannot be undone.") or Simulators.impact(action, self.selected)
	if not self.service.confirmAction(title, message) then return false end
	return self:run(commands, targets, function(row) return Simulators.validate(action, row, self.model) end)
end

function Controller:deleteRuntime()
	if self.busy then return false end
	local row = self.selectedRuntime
	local command = Simulators.runtimeCommand(row, self.model)
	if not command then return false end
	if not self.service.confirmAction("Delete simulator runtime", Simulators.runtimeImpact(row)) then return false end
	return self:run({command}, {row}, function(target) return Simulators.validateRuntime(target, self.model) end)
end

function Controller:dispose()
	self.busy, self.selected, self.selectedRuntime = false, nil, nil
	Page.dispose(self)
end

return Controller
