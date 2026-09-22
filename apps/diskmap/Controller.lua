local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local System = require("apps.diskmap.services.System")
local Controller = {}; Controller.__index = Controller
local function render(name, data) return xml.renderFile("apps/diskmap/views/" .. name .. ".etlua", data or {}, ns) end
local sections = {
	{name = "Storage", icon = "chart.pie.fill"}, {name = "Cleanup", icon = "trash"},
	{name = "Developer", icon = "hammer"}, {name = "Applications", icon = "app"},
}
function Controller.new(service)
	if service == Controller then service = nil end
	service = service or System
	local home = os.getenv("HOME") or "/Users"
	return setmetatable({service = service, home = home, model = Model.new(home), section = "Storage", query = "", generation = 0,
		monitoring = not service.loadSettings or service.loadSettings(), status = "Preparing a complete storage inventory."}, Controller)
end
function Controller:replace(view)
	self.content:clearContainer(); self.content:add(view); self.content:layout()
end
function Controller:capacityText()
	local d = self.disk or {}
	if not d.totalKb then return "Capacity unavailable" end
	return Model.size(d.totalKb * 1024) .. " total  ·  " .. Model.size((d.totalKb - d.freeKb) * 1024) .. " used  ·  " .. Model.size(d.freeKb * 1024) .. " available"
end
function Controller:coverageText()
	local measured = Model.total(self.model)
	local text = Model.size(measured) .. " measured"
	if self.disk then
		local difference = (self.disk.totalKb - self.disk.freeKb) * 1024 - measured
		text = text .. " · " .. (difference < 0 and "−" or "") .. Model.size(math.abs(difference)) .. " unreconciled"
	end
	return text
end
function Controller:visibleRows()
	if self.section == "Cleanup" then
		local rows = {}
		for _, row in ipairs(Model.suggestions(self.model)) do
			if (row.name .. " " .. row.subtitle):lower():find(self.query:lower(), 1, true) then rows[#rows + 1] = row end
		end
		return rows
	end
	return Model.rows(self.model, self.rootId, self.query)
end
function Controller:updateOpportunities()
	if not self.refs or not self.refs.opportunities then return end
	local suggestions = Model.suggestions(self.model)
	while #suggestions > 5 do table.remove(suggestions) end
	local actions = {}
	for i, row in ipairs(suggestions) do actions["review" .. i] = function() self:select(row.id) end end
	local view = render("Opportunities", {suggestions = suggestions, actions = actions})
	self.refs.opportunities:clearContainer(); self.refs.opportunities:add(view); self.refs.opportunities:layout()
end
function Controller:updateStorageBar()
	if not self.refs or not self.refs.storageBar then return end
	local segments, explanation = Model.distribution(self.model, self.disk)
	local actions = {}
	for _, segment in ipairs(segments) do
		actions["category_" .. segment.id] = function()
			if segment.id == "free" then self:openSettings()
			else self:showSection("Storage", self.model.byId[segment.id] and segment.id or nil) end
		end
	end
	local view = render("StorageBar", {segments = segments, explanation = explanation, actions = actions})
	self.refs.storageBar:clearContainer(); self.refs.storageBar:add(view); self.refs.storageBar:layout()
end
function Controller:updateRows()
	if not self.refs or not self.refs.results then return end
	self.refs.results:replaceRows(self:visibleRows())
	if self.capacity then self.capacity.text = self:capacityText(); self.toolbarTitle:layout() end
	self.refs.coverage.text = self:coverageText(); self.refs.status.text = self.status
	self:updateOpportunities()
	self:updateStorageBar()
	if self.job then self.refs.results:showLoading() else self.refs.results:hideLoading() end
end
function Controller:select(id)
	local row = self.model.byId[id]; if not row or not self.refs.detailName then return end
	self.selectedId = id
	local m = self.model.measurements[id]
	self.refs.detailName.text = row.name
	self.refs.detailText.text = row.consequence or row.subtitle .. ". " .. (row.children and "Expand to inspect categories. Measure to check their known locations." or "Review this data in its owning app. Size alone does not establish that it is disposable.")
	self.refs.location.text = (row.path or "Multiple known locations") .. (m and "\n" .. Model.size(m.bytes) .. " · " .. m.status or "")
	self.refs.manage.title = row.action == "trash" and "Review Move to Trash…" or row.action == "settings" and "Open System Settings" or row.action == "xcode" and "Open Xcode" or row.action == "docker" and "Open Docker" or "Reveal in Finder"
	self.refs.manage.enabled = not self.cachePath and not row.children and (row.action ~= "trash" or Model.canTrash(self.model, id)) and (row.path ~= nil or row.action == "settings")
	self.refs.measure.enabled = not self.cachePath and row.id ~= "snapshots"
	self.refs.keep.enabled = true
	self.refs.keep.title = self.model.kept[id] and "Stop keeping this resource" or "Keep this resource"
	self.refs.inspector.hidden = false
	self.refs.inspector:layout()
	self.refs.detailName:scrollIntoView()
end
function Controller:showSection(section, rootId)
	self.section = section
	if self.settingsNavigation then self.settingsNavigation:selectRow(section == "Settings" and 0 or nil) end
	if self.navigation then self.navigation:selectRow(({Storage = 0, Cleanup = 1, Developer = 2, Applications = 3})[section]) end
	self.rootId = rootId or (section == "Developer" and "developer" or section == "Applications" and "applications" or nil)
	if section == "Settings" then
		self.refs = {}
		self:replace(render("Settings", {monitoring = self.monitoring, actions = {
			monitor = function() self.monitoring = not self.monitoring; if self.service.saveSettings then self.service.saveSettings(self.monitoring) end; self:showSection("Settings") end,
			storage = function() self:openSettings() end,
		}})); return
	end
	local root = self.rootId and self.model.byId[self.rootId]
	local suggestions = Model.suggestions(self.model)
	while #suggestions > 5 do table.remove(suggestions) end
	local actions = {
		measure = function() self:scan(self.selectedId or self.rootId) end,
		manage = function() self:manage() end,
		keep = function()
			if not self.selectedId then return end
			self.model.kept[self.selectedId] = not self.model.kept[self.selectedId]
			if not self.cachePath and self.service.saveKeep then
				if not self.service.saveKeep(self.model.kept) then self.status = "Keep preference could not be saved." end
			end
			self:select(self.selectedId); self:updateRows()
		end,
		system = function() self:showSection("Storage", "macos") end,
	}
	for i, row in ipairs(suggestions) do actions["review" .. i] = function() self:select(row.id) end end
	local d = self.disk or {}
	local view, refs = render("Dashboard", {usedFraction = d.totalKb and d.totalKb > 0 and (1 - d.freeKb / d.totalKb) or 0,
		suggestions = suggestions, title = root and root.name or section == "Cleanup" and "Cleanup" or "Storage categories",
		subtitle = root and root.subtitle or "Understand what is stored, why it exists, and how to manage it.", icon = root and root.icon or "chart.pie.fill", color = root and root.color or "systemBlue",
		coverage = self:coverageText(), status = self.status, actions = actions})
	self.refs = refs; self:replace(view)
	refs.results:onRowSelect(function(_, _, row) if row then self:select(row.id) end end)
	refs.results:onRowActivate(function(_, _, row) if row then self:select(row.id) end end)
	self:updateRows()
	if self.selectedId then self:select(self.selectedId) end
end
function Controller:cancel()
	self.generation = self.generation + 1
	if self.job then self.job.cancelled = true; self.service.cancel(self.job); self.job = nil end
	self.status = "Measurement cancelled; previous results retained."
	self:updateRows()
end
function Controller:await(job, completion)
	ns.async(function()
		while not job.cancelled do
			local done, result = self.service.poll(job)
			if done then completion(result); return end
			if result and result.total then
				self.status = string.format("Measuring all storage categories · %d/%d locations", result.completed, result.total)
				if self.refs and self.refs.status then self.refs.status.text = self.status end
			end
			ns.sleep(0.25)
		end
	end)
end
function Controller:scan()
	if self.cachePath then self.status = "Test cache · scanning and cleanup disabled"; self:updateRows(); return end
	self:cancel()
	local paths, ids, exclusions = Inventory.plan(self.model)
	if #paths == 0 then return end
	local ok, job = pcall(self.service.start, paths, exclusions)
	if not ok then self.status = "Could not start measurement: " .. tostring(job); self:updateRows(); return end
	self.job = job; self.status = "Measuring all storage categories…"; self:updateRows()
	local generation = self.generation
	self:await(job, function(result)
		if generation ~= self.generation then return end
		self.job = nil; Inventory.apply(self.model, ids, result)
		self.disk = self.service.diskSpace(self.home)
		self.status = result.failure and result.failure ~= "" and result.failure or "Measured " .. os.date("%H:%M") .. " · " .. (result.errors or 0) .. " unavailable locations"
		if self.writeCache and self.service.writeCache then
			local saved, err = self.service.writeCache(self.writeCache, Inventory.snapshot(self.model, self.disk))
			if not saved then self.status = self.status .. " · Cache not saved: " .. tostring(err) end
		end
		-- Keep the outline mounted so native selection and disclosure survive updates.
		self:updateRows()
		if self.selectedId then self:select(self.selectedId) end
	end)
end
function Controller:openSettings()
	os.execute("/usr/bin/open -a 'System Settings'")
end
function Controller:manage()
	local row = self.model.byId[self.selectedId]
	if not row or self.cachePath then return end
	if row.action == "trash" then
		if not Model.canTrash(self.model, row.id) then return end
		local choice = ns.Alert {title = "Move " .. row.name .. " to Trash?", message = row.path .. "\n\n" .. row.consequence, buttons = {"Cancel", "Move to Trash"}}
		if choice ~= 2 then return end
		local ok, err = self.service.trash(row.path)
		if not ok then ns.Alert {title = "Could not move to Trash", message = err or "Check permissions."}; return end
		self:scan(row.id)
	elseif row.action == "settings" then self:openSettings()
	elseif row.action == "xcode" or row.action == "docker" then os.execute("/usr/bin/open -a " .. System.quote(row.action == "xcode" and "Xcode" or "Docker"))
	elseif row.path then ns.revealInFinder(row.path) end
end
function Controller:createWindow()
	for _, value in ipairs(arg or {}) do
		self.cachePath = value:match("^%-%-?cache=(.+)$") or self.cachePath
		self.writeCache = value:match("^%-%-write%-cache=(.+)$") or self.writeCache
	end
	if not self.cachePath and not self.writeCache and self.service.defaultCachePath then self.writeCache = self.service.defaultCachePath() end
	if not self.cachePath and self.service.loadKeep then
		for id, kept in pairs(self.service.loadKeep()) do if self.model.byId[id] and kept == true then self.model.kept[id] = true end end
	end
	if self.cachePath then
		local data, err = self.service.readCache(self.cachePath)
		if data then
			Inventory.restore(self.model, data)
			self.disk = data.disk; self.status = "Test cache · scanning and cleanup disabled"
		else self.status = "Cache could not be loaded: " .. tostring(err) end
	else self.disk = self.service.diskSpace(self.home) end
	local cfg, windowRefs = render("Window", {capacity = self:capacityText(),
		actions = {search = function(value) self.query = value; self:updateRows() end}})
	local sidebar, sidebarRefs = render("Sidebar")
	local content, contentRefs = render("ContentPane")
	cfg.sidebar = sidebar; cfg.content = content
	self.content = contentRefs.content
	for _, item in ipairs(cfg.toolbar) do
		if item.id == "refresh" then item.action = function() self:scan(self.rootId) end end
		if item.id == "cancel" then item.action = function() self:cancel() end end
	end
	self.settingsNavigation = sidebarRefs.settings
	self.settingsNavigation:replaceRows({{name = "Settings", icon = "gearshape"}})
	self.settingsNavigation:onRowSelect(function(_, _, row) if row and self.section ~= "Settings" then self:showSection("Settings") end end)
	self.navigation = sidebarRefs.navigation
	sidebarRefs.navigation:replaceRows(sections)
	sidebarRefs.navigation:onRowSelect(function(_, _, row) if row and row.name ~= self.section then self:showSection(row.name) end end)
	self.window = ns.Window(cfg)
	self.toolbarTitle = windowRefs.toolbarTitle
	self.capacity = windowRefs.capacity
	self:showSection("Storage")
	sidebarRefs.navigation:selectRow(0)
	if not self.cachePath then self:scan() end
	local scope = ns.Scope.current()
	if scope then scope:add({dispose = function() self:cancel() end}) end
	if not self.cachePath then ns.async(function()
		while self.window.visible do
			ns.sleep(30); self.ticks = (self.ticks or 0) + 1
			if self.window.visible and self.monitoring and not self.job and self.ticks % 30 == 0 then self:scan() end
		end
	end) end
	return self.window
end
return Controller
