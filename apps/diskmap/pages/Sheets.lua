local Provider = require("apps.diskmap.services.Provider")
local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Marks = require("apps.diskmap.models.Marks")
local Categories = require("apps.diskmap.helpers.Categories")
local Cleanup = require("apps.diskmap.helpers.Cleanup")
local Format = require("apps.diskmap.helpers.Format")
local Inspector = require("apps.diskmap.helpers.Inspector")
local Manage = require("apps.diskmap.flows.Manage")
local OperationLog = require("apps.diskmap.helpers.OperationLog")
local Sdks = require("apps.diskmap.helpers.Sdks")
local Selection = require("apps.diskmap.helpers.Selection")
local SheetRoute = require("apps.diskmap.pages.SheetRoute")
local Tour = require("apps.diskmap.helpers.Tour")
local Verify = require("apps.diskmap.helpers.Verify")

-- The sheets of the window. Each is a page of its own over pages/SheetRoute.lua,
-- built by the root controller and drawn into one shell.
local routes = {}

do
	-- The action history sheet: every move, deletion and owner command Diskmap
	-- ran, read back from the operation log each time it is drawn.
	local History = SheetRoute.extend({view = "sheets/History", width = 640, height = 480})
	routes.history = History

	function History:data()
		local service = self.app.service
		local rows = OperationLog.rows(type(service.operationLog) == "function" and service.operationLog() or {})
		return {lists = {entries = rows}, texts = {detail = #rows == 0 and "Diskmap has not changed anything on this Mac yet."
			or (#rows .. (#rows == 1 and " action" or " actions") .. " · also written to ~/Library/Logs/Diskmap/operations.log")}}
	end
end

do
	-- The SDKs one installation holds (an Xcode, the Command Line Tools). Sizes
	-- the discovery did not know are measured once the sheet is up.
	local SdksSheet = SheetRoute.extend({view = "sheets/Sdks", width = 620, height = 480})
	routes.sdks = SdksSheet

	function SdksSheet:init()
		self.service, self.rows, self.query = self.app.service, {}, ""
	end

	function SdksSheet:open(parent, row)
		self.root, self.title, self.query = row.path, row.name, ""
		self.rows = Sdks.discover(self.service, self.root)
		self.unknown = {}
		for _, sdk in ipairs(self.rows) do
			if sdk.bytes == nil then table.insert(self.unknown, sdk) end
		end
		self.measuring = #self.unknown > 0 and type(self.service.measure) == "function"
		SheetRoute.open(self, parent)
	end

	-- Sizes still being measured show one progress state in place of the list.
	function SdksSheet:data()
		local rows = self.measuring and {} or Sdks.filter(self.rows, self.query)
		return {lists = {rows = rows}, loading = {rows = self.measuring}, texts = {title = self.title,
			status = self.measuring and "Measuring SDKs…" or #rows == 0 and "No matching SDKs."
				or (#rows .. (#rows == 1 and " SDK" or " SDKs"))}}
	end

	function SdksSheet:search(value) self.query = value or "" end

	-- Closing the sheet first drops the answer.
	function SdksSheet:activate()
		if not self.measuring then return end
		local rows, slots, paths = self.rows, self.unknown, {}
		for _, sdk in ipairs(slots) do table.insert(paths, sdk.path) end
		self.service.measure(paths, function(sizes)
			if rows ~= self.rows or not self.body then return end
			for index, sdk in ipairs(slots) do
				sdk.bytes = sizes[index] or 0
				sdk.size = Format.size(sdk.bytes)
			end
			self.measuring = false
			self:draw()
		end)
	end

	function SdksSheet:deactivate() self.rows, self.measuring = {}, false end
end

do
	-- Every location that changed since the saved snapshot, in a sheet over the
	-- window. The comparison itself is services/SnapshotComparison.lua.
	local SnapshotChanges = SheetRoute.extend({view = "sheets/SnapshotChanges", width = 720, height = 520})
	routes.snapshotChanges = SnapshotChanges

	SnapshotChanges.queries = {rowMenu = true, reveal = true}

	function SnapshotChanges:open(parent, result)
		self.result = result
		SheetRoute.open(self, parent)
	end

	function SnapshotChanges:data()
		return {lists = {changes = self.result.rows}, texts = {title = self.result.title, detail = self.result.detail}}
	end

	function SnapshotChanges:rowMenu(_, _, row) return row and self:flow("Rows"):resource(row.id) or {} end
	function SnapshotChanges:reveal(_, _, row) if row and row.path then self:flow("Rows"):reveal(row.path) end end
end

do
	-- The settings sheet: switches over the app's persisted flags. `rescan`
	-- restarts measurement after a setting changes what is scanned;
	-- `app.notifications` (services/Notifications.lua) owns the opt-in
	-- notifications. A switch flips before its action runs, so `sync` sets every
	-- switch from the model after each draw: a refused change flips it back.
	local Settings = SheetRoute.extend({view = "sheets/Settings", width = 460, height = 684})
	routes.settings = Settings

	local MEDIA = {
		mock = "Include the synthetic Photos, Music and TV libraries? Mock HDD reads only its bundled fixture.",
		system = "Measuring Photos, Music and TV libraries requires enumerating their files. macOS may ask for access. Diskmap reads metadata only, and keeps measuring them until you turn this off.",
	}

	function Settings:init()
		local service = self.app.service
		self.service, self.notifications = service, self.app.notifications
		if type(Provider.offers(service, "loadFlag")) == "function" then Model.db.includeMedia = service.loadFlag("media") == true end
		self.enabled = not service.loadSettings or service.loadSettings()
		self.history = type(Provider.offers(service, "loadHistorySetting")) == "function" and service.loadHistorySetting() == true
	end

	function Settings:data()
		local available = self.notifications:available()
		self.switches = {monitor = self.enabled, media = Model.db.includeMedia == true, history = self.history,
			reminder = self.notifications:enabled("reminder"), sentinel = self.notifications:enabled("sentinel")}
		return {disabled = {reminder = not available, sentinel = not available}, hidden = {notificationsUnavailable = available}}
	end

	function Settings:sync(refs)
		for id, on in pairs(self.switches) do refs[id].state = on and 1 or 0 end
	end

	-- Storage history is opt-in; turning it off also forgets what was recorded.
	function Settings:toggleHistory()
		local enabled = not self.history
		if self.service.saveHistorySetting and not self.service.saveHistorySetting(enabled) then
			self.service.showError("Could not save Settings", "Try again.")
			return false
		end
		self.history = enabled
		if not enabled and self.service.saveHistory then self.service.saveHistory("") end
		return true
	end

	-- The reminder describes storage history, so turning it on turns history on
	-- too. The switch stays off when macOS refuses permission.
	function Settings:toggleNotification(name)
		local enabled = not self.notifications:enabled(name)
		if enabled and name == "reminder" and not self.history and not self:toggleHistory() then return self:draw() end
		self.notifications:setEnabled(name, enabled, function(on)
			if enabled and not on then
				self.service.showError("Notifications are off for Diskmap", "Allow them in System Settings › Notifications › Diskmap.")
			end
			self:draw()
		end)
		self:draw()
	end

	function Settings:toggleReminder() self:toggleNotification("reminder") end
	function Settings:toggleSentinel() self:toggleNotification("sentinel") end

	function Settings:toggle()
		local enabled = not self.enabled
		if self.service.saveSettings and not self.service.saveSettings(enabled) then return false end
		self.enabled = enabled; return true
	end

	function Settings:toggleMonitor()
		if not self:toggle() then self.service.showError("Could not save Settings", "Try again.") end
	end

	-- The choice is kept between launches: someone whose disk is full of photos
	-- should not have to find the switch again every time.
	function Settings:setMedia(enabled)
		Model.db.includeMedia = enabled
		if type(Provider.offers(self.service, "saveFlag")) == "function" then self.service.saveFlag("media", enabled) end
		self.app.rescan()
	end

	function Settings:toggleMedia()
		if Model.db.includeMedia then return self:setMedia(false) end
		local message = Provider.offers(self.service, "mock") == true and MEDIA.mock or MEDIA.system
		if self.service.confirmAction("Include media libraries", message) then self:setMedia(true) end
	end

	function Settings:openStorage() self.service.openSettings() end
	function Settings:openPrivacy() self.service.openSettings("privacy") end
end

do
	-- The cleanup basket and its review sheet. Pages mark items through
	-- `toggle`; nothing touches the disk until the sheet's Move to Trash, which
	-- revalidates each item, moves it, logs it, and then offers to empty the
	-- Trash so the freed space can be measured rather than assumed. The sheet is
	-- drawn from `data()` (views/sheets/Review.etlua); the app hears of marks through
	-- `app.basketChanged`, of remeasuring through `app.rescan`.
	local Review = SheetRoute.extend({view = "sheets/Review", width = 620, height = 560})
	routes.review = Review

	function Review:init()
		self.service = self.app.service
		self.results, self.done = {}, {}
	end

	function Review:log(action, ok, bytes, target, detail)
		if type(self.service.logOperation) ~= "function" then return end
		self.service.logOperation(OperationLog.format({action = action, ok = ok, bytes = bytes, target = target, detail = detail}))
	end

	function Review:isMarked(path) return path ~= nil and Marks:contains(path) end
	function Review:covering(path) return Marks:covering(path) end
	function Review:summary() return Marks:summary() end
	function Review:count() return Marks:count() end

	-- Identity and basket validation are identical for individual and bulk
	-- staging. Only the caller publishes, so a bulk click refreshes UI once.
	local function add(self, item)
		local valid, why = Marks.validate(item.path, Model.db.home)
		if not valid then return false, why end
		local identity = Provider.offers(self.service, "fileIdentity")
		if type(identity) == "function" and not item.identity then item.identity = identity(item.path) end
		local ok, reason = Marks:add(item)
		if ok then
			self.results[item.path] = nil
			self.done[item.path] = nil
		end
		return ok, reason
	end

	-- Marks or unmarks an item {path, name, bytes, consequence, source,
	-- resourceId}. Returns marked state and a refusal message.
	function Review:toggle(item)
		if type(item) ~= "table" or not item.path then return false, "Nothing selected." end
		if Marks:contains(item.path) then
			Marks:remove(item.path)
			self.app.basketChanged()
			return false
		end
		local ok, reason = add(self, item)
		self.app.basketChanged()
		return ok, reason
	end

	function Review:markAll(items)
		local count = 0
		for _, item in ipairs(items) do
			if type(item) == "table" and item.path and not self:covering(item.path) and add(self, item) then count = count + 1 end
		end
		if count > 0 then self.app.basketChanged() end
		return count
	end

	-- The sheet opens on `path`'s item, or on the first.
	function Review:open(parent, path)
		self.done, self.status, self.movedBytes = {}, nil, nil
		self.selectedPath = path or ((Marks:all()[1] or {}).path)
		SheetRoute.open(self, parent)
	end

	function Review:data()
		local rows, bytes = Marks:rows()
		for _, row in ipairs(rows) do row.result = self.results[row.path] or "" end
		for path, result in pairs(self.done) do
			table.insert(rows, {id = path, path = path, name = path:match("([^/]+)$"), subtitle = path, size = "", result = result})
		end
		self.rows, self.selected = rows, nil
		for _, row in ipairs(rows) do
			if row.path == self.selectedPath then self.selected = row end
		end
		if not self.selected then self.selectedPath = nil end
		local selected, pending, busy = self.selected, Marks:count(), self.busy == true
		return {
			-- Measuring again shows one progress state in place of the list.
			lists = {items = busy and {} or rows}, loading = {items = busy},
			texts = {
				reviewSummary = self.status or (pending == 0 and "Nothing marked. Use Mark for Cleanup on any page."
					or (pending .. (pending == 1 and " item · " or " items · ") .. Format.size(bytes) .. " on disk")),
				selectedPath = selected and selected.path or "",
				consequence = selected and (selected.consequence or "This item has already left the cleanup basket.") or "",
				selectedResult = selected and selected.result or "",
			},
			hidden = {selectedDetails = selected == nil, emptyTrash = (self.movedBytes or 0) <= 0},
			disabled = {remove = busy or not (selected and Marks:contains(selected.path)),
				trash = busy or pending == 0, clear = busy or pending == 0},
		}
	end

	-- After a draw the native selection follows the selected row.
	function Review:sync(refs)
		Selection.show(refs.items, self.rows, self.selectedPath)
	end

	function Review:select(_, _, row) self.selectedPath = row and row.path end

	function Review:remove()
		if self.selected then Marks:remove(self.selected.path) end
		self.app.basketChanged()
	end

	function Review:clear()
		Marks:clear()
		self.app.basketChanged()
	end

	function Review:history()
		self:close()
		self.app.openHistory()
	end

	-- Moves every marked item to the Trash. Sizes are measured again first,
	-- because a mark can be hours old, and each item is checked again just
	-- before it moves (helpers/Verify.lua): an item whose app is running, whose
	-- proof is gone or that was replaced is skipped with its reason. Results
	-- are reported per item and summarised; nothing is rolled back or retried.
	function Review:trash()
		if Marks:count() == 0 or self.busy then return false end
		local paths = {}
		for _, mark in ipairs(Marks:all()) do table.insert(paths, mark.path) end
		local measure = Provider.offers(self.service, "measure")
		if type(measure) ~= "function" then return self:moveAll(paths) end
		self.busy = true
		self.status = "Measuring marked items again…"; self:draw()
		local finished
		measure(paths, function(sizes)
			self.busy = false
			for index, path in ipairs(paths) do
				local item = Marks:find(path)
				if item and sizes and sizes[index] and sizes[index] > 0 then item.bytes = sizes[index] end
			end
			self.status = nil
			finished = self:moveAll(paths)
		end)
		return finished ~= false
	end

	function Review:probes()
		local probes = Provider.offers(self.service, "cleanupProbes")
		return type(probes) == "function" and probes() or {}
	end

	function Review:moveAll(paths)
		local rows, bytes = Marks:rows()
		if #rows == 0 then return false end
		local names = {}
		for index, row in ipairs(rows) do if index <= 12 then table.insert(names, "· " .. row.name .. " (" .. row.size .. ")") end end
		if #rows > 12 then table.insert(names, "· and " .. (#rows - 12) .. " more") end
		if not self.service.confirmAction("Move to Trash", table.concat(names, "\n") .. "\n\n" .. Format.size(bytes)
			.. " moves to the Trash. You can put items back from the Trash in Finder until you empty it.") then self:draw(); return false end
		self.busy = true
		local home = Model.db.home
		local before = self.service.diskSpace(home)
		local probes = self:probes()
		local result = {moved = 0, movedBytes = 0, skipped = {}}
		for _, path in ipairs(paths) do
			local item = Marks:find(path)
			if item then
				local resource = item.resourceId and Locations:find(item.resourceId)
				local ok, message
				local allowed, why = Verify.check(item, resource, home, probes)
				if not allowed then
					ok, message = false, "Skipped: " .. why.reason
					table.insert(result.skipped, why.reason)
				elseif item.resourceId then
					local done, err = Cleanup.moveToTrash(item.resourceId, self.service)
					ok, message = done, err and err.message
				else
					local pcallOk, moved, detail = pcall(self.service.trash, path)
					ok, message = pcallOk and moved == true, pcallOk and detail or tostring(moved)
				end
				self:log("Move to Trash", ok, item.bytes, path, message)
				if ok then
					result.moved, result.movedBytes = result.moved + 1, result.movedBytes + (item.bytes or 0)
					self.done[path] = "Moved to Trash"
					Marks:remove(path)
				else
					if allowed then table.insert(result.skipped, "it could not be moved (" .. tostring(message or "unknown error") .. ")") end
					self.results[path] = allowed and ("Failed: " .. tostring(message or "unknown error")) or "Skipped"
				end
			end
		end
		local after = self.service.diskSpace(home)
		result.freeBefore = before and before.freeKb and before.freeKb * 1024 or nil
		result.freeNow = after and after.freeKb and after.freeKb * 1024 or nil
		self.busy = false
		self.movedBytes = (self.movedBytes or 0) + result.movedBytes
		self.lastResult = result
		self.status = Verify.summary(result)
		self.app.basketChanged()
		self.app.rescan()
		self:draw()
		return true
	end

	-- Empties the Trash through Finder and reports the change in free space
	-- macOS observes, which can differ from the moved size (snapshots keep
	-- blocks; other apps write meanwhile).
	function Review:emptyTrash()
		if not self.service.emptyTrash or not self.service.confirmAction("Empty Trash",
			"Permanently removes everything in the Trash, including items you moved there before. This cannot be undone.") then return false end
		local home = Model.db.home
		local before = self.service.diskSpace(home)
		local ok = self.service.emptyTrash()
		local after = self.service.diskSpace(home)
		local freed = before and after and (after.freeKb - before.freeKb) * 1024 or nil
		self:log("Empty Trash", ok == true, freed and math.max(0, freed) or 0, "~/.Trash")
		self.movedBytes = nil
		if ok and freed and freed > 0 then
			self.status = "Emptied the Trash. macOS now reports " .. Format.size(freed) .. " more free space."
		elseif ok then
			self.status = "Emptied the Trash. Free space has not changed yet; local snapshots may still hold the blocks."
		else
			self.status = "The Trash could not be emptied."
		end
		self.app.rescan()
		self:draw()
		return ok
	end
end

do
	-- A category's list of locations, as a sheet over the window: one list per
	-- impact tab, searchable and sortable, with the selected location's
	-- actions below. `app.open(id)` opens a resource wherever its location
	-- sends it; a row that lives on a page or sheet of its own leaves this one.
	local ManagementSheet = SheetRoute.extend({view = "sheets/Management", width = 620, height = 640})
	routes.management = ManagementSheet

	ManagementSheet.filters = {"All", "Safe/rebuildable", "Needs review", "Essential to keep"}
	ManagementSheet.queries = {reveal = true}

	local function sortRows(rows, column, ascending)
		local function value(row)
			if column == "size" then return row.bytes end
			return row[column]
		end
		table.sort(rows, function(left, right)
			local a, b = value(left), value(right)
			if a == nil or b == nil then
				if a == nil and b ~= nil then return false end
				if a ~= nil and b == nil then return true end
			else
				if type(a) == "string" then a, b = a:lower(), b:lower() end
				if a ~= b then
					if ascending then return a < b end
					return a > b
				end
			end
			local leftName, rightName = left.name:lower(), right.name:lower()
			if leftName ~= rightName then return leftName < rightName end
			return left.id < right.id
		end)
		return rows
	end

	function ManagementSheet:init()
		self.service = self.app.service
	end

	-- `options.select` is the location to select and scroll to; `options.filter`
	-- the impact tab to show. The list always opens largest first.
	function ManagementSheet:open(parent, id, options)
		options = options or {}
		self.rootId, self.query, self.sortColumn, self.sortAscending = id, "", "size", false
		self.selectedId, self.tab, self.openTab, self.snapshotNote = options.select, options.filter or "All", options.filter, nil
		SheetRoute.open(self, parent)
	end

	-- While a scan measures, the sheet shows one progress state in place of its
	-- lists; the locations appear once their sizes are known.
	function ManagementSheet:data()
		local resources, scanning = Model.db.resources, self.app.scanning()
		local lists, tabRows, loading = {}, {}, {}
		for index, filter in ipairs(self.filters) do
			local rows = scanning and {} or sortRows(Categories.managementRows(self.rootId, self.query, filter),
				self.sortColumn, self.sortAscending)
			lists["rows" .. index], tabRows[filter], loading["rows" .. index] = rows, rows, scanning
		end
		-- Only a row of the tab that shows can stay selected.
		local selected = self.selectedId
		if not scanning then
			local visible
			for _, row in ipairs(tabRows[self.tab] or {}) do if row.id == selected then visible = true end end
			if not visible then selected = nil end
		end
		self.selectedId, self.tabRows = selected, tabRows
		local total = #lists.rows1
		local summary = scanning and "Measuring…" or total == 0 and "No matching resources."
			or total .. (total == 1 and " resource" or " resources")
		local row = selected and not scanning and Locations:find(selected)
		local detail = row and Inspector.details(selected)
		local root = Locations:find(self.rootId)
		return {
			title = root and root.name or "Safe reclaim potential", category = Inspector.details(self.rootId),
			filters = self.filters, manageTitle = detail and detail.manageTitle or "Review",
			lists = lists, loading = loading,
			texts = {status = detail and detail.location or (self.snapshotNote and self.snapshotNote .. " · " .. summary or summary),
				keep = detail and detail.keepTitle or "Keep"},
			hidden = {manage = row and row.action == "finder" or false},
			disabled = {manage = not (detail and detail.canManage), reveal = not (row and row.path), keep = detail == nil},
		}
	end

	-- After a draw: the sort arrows, the tab the person asked for, and the
	-- selected row in the tab that shows.
	function ManagementSheet:sync(refs)
		for index, filter in ipairs(self.filters) do
			local list = refs["rows" .. index]
			list:setSortIndicator(self.sortColumn, self.sortAscending)
			if filter == self.tab then Selection.show(list, self.tabRows[filter], self.selectedId) end
		end
		if self.openTab then
			for index, filter in ipairs(self.filters) do
				if filter == self.openTab then refs.tabs:selectTab(index - 1) end
			end
			self.openTab = nil
		end
	end

	-- The count of local snapshots joins the status line of System Data.
	function ManagementSheet:activate()
		if self.rootId ~= "system-data" or not self.service.snapshotCount then return end
		local sheet = self.sheet
		self.service.snapshotCount(function(count, dates)
			if count == nil or self.sheet ~= sheet then return end
			local note = count == 0 and "No local snapshots" or (tostring(count) .. " local snapshots")
			if count > 0 and dates and #dates > 0 then
				local shown = {}; for index = math.max(1, #dates - 3), #dates do table.insert(shown, (dates[index]:match("TimeMachine%.(.+)%.local$"))) end
				note = note .. " · " .. table.concat(shown, ", ") .. (#dates > #shown and " …" or "")
			end
			self.snapshotNote = note
			self:draw()
		end)
	end

	function ManagementSheet:search(value) self.query = value or "" end

	function ManagementSheet:sortBy(column)
		if column ~= "name" and column ~= "impact" and column ~= "size" then return end
		if self.sortColumn == column then self.sortAscending = not self.sortAscending
		else self.sortColumn = column; self.sortAscending = true end
		self:draw()
	end

	function ManagementSheet:sort(_, column) self:sortBy(column) end
	function ManagementSheet:select(_, _, row) if row then self.selectedId = row.id end end

	function ManagementSheet:tabChanged()
		self.tab, self.selectedId = self.refs.tabs.selectedTabViewItem.label, nil
	end

	function ManagementSheet:categoryRefresh() self.app.rescan() end
	function ManagementSheet:categoryKeep() self.app.keep(self.rootId) end
	function ManagementSheet:keep() if self.selectedId then self.app.keep(self.selectedId) end end

	function ManagementSheet:reveal()
		local row = Locations:find(self.selectedId)
		if row and row.path then self.service.reveal(row.path) end
	end

	function ManagementSheet:review(id, manage)
		local row = Locations:find(id)
		if not row then return end
		if Locations:opensElsewhere(id) then self.app.open(id); return end
		if not manage then return end
		self:flow("Manage"):manage(row.id)
	end

	function ManagementSheet:manage() self:review(self.selectedId, true) end
	function ManagementSheet:reviewRow(_, _, row) if row then self:review(row.id) end end
end

do
	-- First-launch access onboarding (#52, after Headroom's), shown before the
	-- first scan when the provider can tell that access is missing. It has two
	-- stages. "disk" comes first in the App Store build while Diskmap has no
	-- access to the startup disk: the App Sandbox shows it only what the person
	-- chooses in an open panel, whatever Full Disk Access says. It returns on
	-- every launch until the disk is chosen, as a scan without it measures
	-- nothing. "fullDisk" asks once for Full Disk Access; while it is open
	-- Diskmap checks access every second and, once it is granted, closes the
	-- sheet and starts the scan by itself. "Continue Without Access" is always
	-- there. `app.onboarded(granted)` starts the scan.
	local Onboarding = SheetRoute.extend({view = "sheets/Onboarding", width = 580, height = 390})
	routes.onboarding = Onboarding

	Onboarding.interval = 1

	function Onboarding:init()
		self.service = self.app.service
	end

	local function call(service, name, ...)
		local fn = Provider.offers(service, name)
		if type(fn) == "function" then return fn(...) end
	end

	-- "disk" while a provider that can tell (the sandboxed Mac) has no access
	-- to the startup disk, otherwise "fullDisk".
	function Onboarding:stage()
		if call(self.service, "hasDiskAccess") == false then return "disk" end
		return "fullDisk"
	end

	-- Needed when the provider reports access (a real Mac does; the synthetic
	-- disk does not) and it is missing: the disk on every launch, Full Disk
	-- Access until onboarding has been shown.
	function Onboarding:needed()
		if type(Provider.offers(self.service, "hasFullDiskAccess")) ~= "function" then return false end
		if self:stage() == "disk" then return true end
		if call(self.service, "loadFlag", "onboarded") == true then return false end
		return self.service.hasFullDiskAccess() ~= true
	end

	function Onboarding:data()
		local waiting = self.openedSettings == true
		return {stage = self:stage(), hidden = {waiting = not waiting, restart = not waiting}}
	end

	function Onboarding:open(parent)
		self.openedSettings = false
		SheetRoute.open(self, parent)
		self:every(Onboarding.interval, function() self:poll() end)
	end

	-- Continues once Full Disk Access has been granted. Returns whether it did.
	function Onboarding:poll()
		if not self.sheet or self:stage() ~= "fullDisk" then return false end
		if self.service.hasFullDiskAccess() == true then self:finish(true); return true end
		return false
	end

	-- The open panel for the startup disk. Once it is chosen the sheet moves on
	-- to Full Disk Access, or closes when that is already on.
	function Onboarding:chooseDisk()
		if not call(self.service, "requestDiskAccess") then return false end
		if self.service.hasFullDiskAccess() == true or call(self.service, "loadFlag", "onboarded") == true then
			self:finish(self.service.hasFullDiskAccess() == true)
			return true
		end
		self:draw()
		return true
	end

	function Onboarding:openSettings()
		self.service.openSettings("privacy")
		self.openedSettings = true
		self:draw()
	end

	-- Starts a new instance and quits once it runs; the new one skips the
	-- sheet if access now works, or shows it again.
	function Onboarding:restart()
		local relaunch = Provider.offers(self.service, "relaunch")
		if type(relaunch) ~= "function" then return false end
		relaunch(function(message) self.service.showError("Diskmap could not restart", message or "Quit and open Diskmap again.") end)
		return true
	end

	function Onboarding:skip() self:finish(false) end

	function Onboarding:finish(granted)
		if not self.sheet then return end
		call(self.service, "saveFlag", "onboarded", true)
		self:close()
		self.app.onboarded(granted)
	end
end

do
	-- The welcome tour sheet: on start, after any access steps and while the
	-- scan runs, until "Show this window on start" is turned off, and whenever
	-- Help > Diskmap Tour opens it. Skip closes it at any page. Pages slide in
	-- from the side they come from: Continue brings the next one in from the
	-- trailing edge, Back the previous one from the leading edge.
	local TourSheet = SheetRoute.extend({view = "sheets/Tour", width = 580, height = 540})
	routes.tour = TourSheet

	function TourSheet:init()
		self.service, self.page = self.app.service, 1
	end

	local function call(service, name, ...)
		local fn = Provider.offers(service, name)
		if type(fn) == "function" then return fn(...) end
	end

	-- On a real Mac only: the synthetic disk (no access probe) is for demos
	-- and screenshots, which a tour would cover. The flag is stored inverted
	-- so that a new install, with no flags, shows the tour.
	function TourSheet:showOnStart() return call(self.service, "loadFlag", "hideTour") ~= true end
	function TourSheet:setShowOnStart(show) call(self.service, "saveFlag", "hideTour", not show) end
	function TourSheet:toggleShowOnStart() self:setShowOnStart(not self:showOnStart()) end

	function TourSheet:needed(disk)
		if type(Provider.offers(self.service, "hasFullDiskAccess")) ~= "function" then return false end
		-- A storage alert needs a direct route to findings. The tour remains
		-- available from Help, and the person’s show-on-start choice is preserved.
		if disk and disk.totalKb and disk.totalKb > 0 and disk.freeKb and disk.freeKb / disk.totalKb < 0.1 then return false end
		return self:showOnStart()
	end

	function TourSheet:open(parent)
		if self.sheet or parent.attachedSheet then return false end
		self.page = 1
		SheetRoute.open(self, parent)
		return true
	end

	function TourSheet:data()
		local last = self.page == #Tour.pages
		return {pages = Tour.pages, current = self.page, showOnStart = self:showOnStart(),
			texts = {next = last and "Start Using Diskmap" or "Continue"}, hidden = {back = self.page == 1}}
	end

	function TourSheet:show(index)
		if not self.sheet then return end
		local previous = self.page
		self.page = math.max(1, math.min(index, #Tour.pages))
		if previous ~= self.page then self.slide = {id = "pages", edge = self.page > previous and "trailing" or "leading"} end
		self:draw()
	end

	function TourSheet:back() self:show(self.page - 1) end
	function TourSheet:goTo(page) self:show(page + 1) end

	-- Continue, or Start Using Diskmap on the last page.
	function TourSheet:next()
		if self.page == #Tour.pages then self:close() else self:show(self.page + 1) end
	end
end

return routes
