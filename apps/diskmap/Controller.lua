local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local System = require("apps.diskmap.services.System")
local VIEWS = "apps/diskmap/views/"
local Controller = {}
Controller.__index = Controller
local function render(name, data) return xml.renderFile(VIEWS .. name .. ".etlua", data or {}, ns) end
function Controller.new(service)
	if service == Controller then service = nil end
	local home = os.getenv("HOME") or "/Users"
	service = service or System
	local monitoring = not service.loadSettings or service.loadSettings()
	return setmetatable({service = service or System, home = home, rules = Model.rules(home), section = "Disk Map", query = "", history = {}, forward = {}, suggestions = {}, monitoring = monitoring, generation = 0, checked = {}, measurements = {trees = {}, rootStates = {}}}, Controller)
end
function Controller:replace(pane, view)
	pane:clearContainer(); pane:add(view); pane:layout()
end
function Controller:showDetail(row)
	self.selected = row
	row = row or {}
	local review = row.consequence ~= nil
	local data = {
		name = row.name or "Storage insights", path = row.path or "", size = row.size or "",
		icon = review and "lightbulb" or (row.directory and "folder.fill" or "doc"),
		heading = review and row.risk or "About this selection",
		message = row.consequence or (row.path and ((row.items and (tostring(row.items) .. " items measured. ") or "") .. "Double-click a folder to scan its contents. Files open in Finder for review. Sizes reflect allocated storage, including hidden files.") or "Select an item to inspect it. Suggestions explain what removal changes before you act."),
		review = review, hasPath = row.path ~= nil,
		outcome = row.action == "trash" and (row.size .. " measured. Space is released only after you empty Trash in Finder. APFS snapshots may retain blocks; future cache growth is expected.") or "This is measured storage, not a reclaimable-space promise. Review individual items in the owning application before removing them.",
		primary = row.action == "measure" and "Measure This Location…" or row.action == "trash" and "Review Move to Trash…" or row.action == "xcode" and "Open Xcode" or row.action == "docker" and "Open Docker" or "Review in Finder",
		actions = {
			primary = function() self:review(row) end,
			reveal = function() ns.revealInFinder(row.path) end,
			copy = function() ns.copyToClipboard(row.path) end,
			terminal = function() os.execute("/usr/bin/open -a Terminal " .. System.quote(row.directory == false and (row.path:match("^(.*)/") or "/") or row.path)) end,
			suggestions = function() self:showSection("Suggestions") end,
		},
	}
	self:replace(self.refs.detail, render("RightSidebar", data))
end
function Controller:review(row)
	if row.action == "measure" then
		self:scanSuggestions(row.id)
	elseif row.action == "trash" then
		local choice = ns.Alert {title = "Move " .. row.name .. " to Trash?", message = row.path .. "\n\n" .. row.consequence .. "\n\n" .. row.size .. " measured at the last scan. No space is freed until Trash is emptied in Finder. You can restore the folder from Trash before then.", buttons = {"Cancel", "Move to Trash"}}
		if choice ~= 2 then return end
		local ok, err = Model.trash(row, self.rules, self.service)
		if not ok then ns.Alert {title = "Could not move to Trash", message = err or "Check access permissions and try again."}; return end
		self:scanSuggestions()
		self.result = nil
		if self.section ~= "Suggestions" and self.currentPath then self:startScan(self.currentPath, true) end
	elseif row.action == "xcode" or row.action == "docker" then
		local app = row.action == "xcode" and "Xcode" or "Docker"
		local ok = os.execute("/usr/bin/open -a " .. System.quote(app))
		if not ok then ns.Alert {title = app .. " could not be opened", message = "Open the application manually, or reveal the measured location in Finder."} end
	else ns.revealInFinder(row.path) end
end
function Controller:visibleRows()
	if self.section ~= "Suggestions" then return Model.rows(self.result or {}, self.section, self.query) end
	local rows = {}
	for _, row in ipairs(self.suggestions) do if row.name:lower():find(self.query:lower(), 1, true) then rows[#rows + 1] = row end end
	return rows
end
function Controller:updateToolbar()
	if not self.window then return end
	for id, enabled in pairs({back = #self.history > 0, forward = #self.forward > 0, up = self.result ~= nil and self.currentPath ~= "/", cancel = self.scanJob ~= nil}) do
		local item = ns.ToolbarItem(self.window, id)
		item.enabled = enabled
		if item.view then item.view.enabled = enabled end
	end
end
function Controller:updateRows()
	if not self.results then return end
	local rows = self:visibleRows()
	self.results:replaceRows(rows)
	local status = self.section == "Suggestions" and self.suggestionStatus or self.scanStatus
	self.status.text = (status or "Ready") .. " · " .. #rows .. " results"
end
function Controller:showSection(section)
	self.section = section
	if self.navigation then
		local indices = {["Disk Map"] = 0, Suggestions = 1, ["Large Files"] = 2, Applications = 3, ["File Types"] = 4}
		self.navigation:selectRow(indices[section])
	end
	if section == "Applications" and not self.currentPath then self:startScan("/Applications", true); return end
	self.results = nil
	if section == "Settings" then
		self:replace(self.refs.content, render("Settings", {monitoring = self.monitoring, actions = {
			monitor = function()
				self.monitoring = not self.monitoring
				if self.service.saveSettings and not self.service.saveSettings(self.monitoring) then ns.Alert {title = "Settings could not be saved", message = "This choice applies until Diskmap closes."} end
				self:showSection("Settings")
				if self.monitoring then self:scanSuggestions() end
			end,
			storage = function() os.execute("/usr/bin/open 'x-apple.systempreferences:com.apple.settings.Storage'") end,
		}}))
		return
	end
	local subtitle = self.currentPath or "Choose a folder to measure. Only filenames and size metadata are examined."
	if section == "Suggestions" then subtitle = Model.humanKb(self.reclaimable) .. " in rebuildable caches · other categories require individual review"
	elseif section == "Large Files" then subtitle = subtitle .. " · largest 500 files of at least 1 MB"
	elseif section == "Applications" then subtitle = subtitle .. " · application bundles in this scan"
	elseif section == "File Types" then subtitle = subtitle .. " · allocated space grouped by filename extension" end
	local view, refs = render("Dashboard", {title = section, section = section, subtitle = subtitle, segments = section == "Disk Map" and Model.segments(self.result or {}) or {}, status = "Preparing…", hasScan = self.currentPath ~= nil or section == "Suggestions", actions = {refresh = function() self:rescan() end}})
	self:replace(self.refs.content, view)
	self.results = refs.results; self.status = refs.status
	self.results:onRowSelect(function(_, _, row) if row then self:showDetail(row) end end)
	self.results:onRowActivate(function(_, _, row)
		if not row then return end
		if section == "Suggestions" then self:showDetail(row)
		elseif row.path and row.directory then self.section = "Disk Map"; self:startScan(row.path)
		elseif row.path then ns.revealInFinder(row.path) end
	end)
	self:updateRows()
	if (section == "Suggestions" and self.suggestionJob) or (section ~= "Suggestions" and self.scanJob) then self.results:showLoading() end
end
function Controller:await(job, completion)
	ns.async(function()
		while not job.cancelled do
			local done, result = self.service.poll(job)
			if done then completion(result); return end
			ns.sleep(0.25)
		end
	end)
end
function Controller:cancel(job)
	if job then job.cancelled = true; self.service.cancel(job) end
end
function Controller:startScan(path, navigation)
	path = path:gsub("/+$", ""); if path == "" then path = "/" end
	if not navigation and self.currentPath and self.currentPath ~= path then self.history[#self.history + 1] = self.currentPath; self.forward = {} end
	self.currentPath = path
	self:cancel(self.scanJob)
	self.generation = self.generation + 1
	local generation = self.generation
	self.result = nil; self.scanStatus = "Scanning in background…"
	local ok, job = pcall(self.service.start, {path})
	if not ok then self.scanStatus = "Cannot start scan: " .. tostring(job); self:showSection(self.section); return end
	self.scanJob = job
	self:updateToolbar()
	self:showSection(self.section)
	self:showDetail()
	self:await(job, function(result)
		if generation ~= self.generation then return end
		self.scanJob = nil
		self:updateToolbar()
		self.result = result
		self.scanStatus = result.failure and result.failure ~= "" and result.failure or ("Scanned in " .. (result.seconds or 0) .. "s · " .. (result.errors or 0) .. " unreadable locations")
		self:updateCapacity()
		if self.section ~= "Settings" and self.section ~= "Suggestions" then
			self:showSection(self.section)
			local root = result.trees and result.trees[1]
			if type(root) == "table" then root.size = Model.humanKb(root.kb); self:showDetail(root) end
		end
	end)
end
function Controller:scanSuggestions(ruleId)
	if self.suggestionJob then return end
	local paths, indices = {}, {}
	for i, rule in ipairs(self.rules) do
		if ruleId and rule.id == ruleId or not ruleId and rule.automatic then
			paths[#paths + 1] = rule.path; indices[#indices + 1] = i
		end
	end
	if #paths == 0 then return end
	local ok, job = pcall(self.service.start, paths, "summary")
	if not ok then self.suggestionStatus = "Could not start suggestions scan"; return end
	self.suggestionJob = job; self.suggestionStatus = "Checking known locations…"
	if self.section == "Suggestions" then self:showSection("Suggestions") end
	self:await(job, function(result)
		self.suggestionJob = nil
		for position, index in ipairs(indices) do
			self.checked[index] = true
			self.measurements.trees[index] = result.trees and result.trees[position]
			self.measurements.rootStates[index] = result.rootStates and result.rootStates[position] or "unreadable"
		end
		self.suggestions, self.reclaimable = Model.suggestions(self.rules, self.measurements, self.checked)
		self.suggestionStatus = result.failure and result.failure ~= "" and result.failure or ("Checked " .. os.date("%H:%M") .. " · " .. (result.errors or 0) .. " unavailable locations")
		if self.section == "Suggestions" then self:showSection("Suggestions"); self:showDetail() end
	end)
end
function Controller:updateCapacity()
	local disk = self.service.diskSpace(self.currentPath or self.home)
	if disk and self.capacity then
		self.capacity.text = Model.humanKb(disk.totalKb) .. " total · " .. Model.humanKb(disk.freeKb) .. " free"
		self.toolbarTitle:layout()
	end
end
function Controller:goBack()
	if #self.history == 0 then return end
	self.forward[#self.forward + 1] = self.currentPath
	self:startScan(table.remove(self.history), true)
end
function Controller:goForward()
	if #self.forward == 0 then return end
	self.history[#self.history + 1] = self.currentPath
	self:startScan(table.remove(self.forward), true)
end
function Controller:chooseFolder()
	local path = self.service.pickFolder()
	if path then self.section = "Disk Map"; self:startScan(path) end
end
function Controller:rescan()
	if self.section ~= "Suggestions" and not self.currentPath then self:chooseFolder(); return end
	if self.section == "Suggestions" then self:scanSuggestions() else self:startScan(self.currentPath, true) end
end
function Controller:createWindow()
	local cfg = render("Window")
	local actions = {
		choose = function() self:chooseFolder() end,
		back = function() self:goBack() end, forward = function() self:goForward() end,
		up = function() if not self.currentPath then return end; self:startScan(self.currentPath:match("^(.*)/[^/]+$") or "/") end,
		cancel = function()
			self:cancel(self.scanJob); self.scanJob = nil; self.generation = self.generation + 1
			self.scanStatus = "Scan cancelled"; self:updateToolbar()
			if self.section ~= "Settings" then self:showSection(self.section) end
		end,
		refresh = function() self:rescan() end, toggleDetail = function() self.window:toggleDetail() end,
	}
	for _, item in ipairs(cfg.toolbar) do item.action = actions[item.id] end
	local sidebar, sidebarRefs = render("Sidebar", {actions = {settings = function() self:showSection("Settings") end}})
	local content, contentRefs = render("ContentPane")
	local detail, detailRefs = render("DetailPane")
	cfg.sidebar = sidebar; cfg.content = content; cfg.detail = detail
	self.refs = {content = contentRefs.content, detail = detailRefs.detail}
	local navigation = {}
	local icons = {"chart.pie", "lightbulb", "doc", "app", "doc.on.doc"}
	for i, name in ipairs({"Disk Map", "Suggestions", "Large Files", "Applications", "File Types"}) do navigation[#navigation + 1] = {name = name, icon = icons[i]} end
	self.navigation = sidebarRefs.navigation
	sidebarRefs.navigation:replaceRows(navigation)
	sidebarRefs.navigation:onRowSelect(function(_, _, row) if row and row.name ~= self.section then self:showSection(row.name) end end)
	self.window = ns.Window(cfg)
	self.window.contentViewController.splitViewItems[1].maximumThickness = cfg.sidebarWidth
	local scope = ns.Scope.current()
	if scope then scope:add({dispose = function() self:cancel(self.scanJob); self:cancel(self.suggestionJob) end}) end
	local title, titleRefs = render("ToolbarTitle")
	title.frame = ns.Rect(ns.Point(0, 0), ns.Size(title.fixedWidth, title.fixedHeight))
	title:layout(title.fixedWidth)
	ns.ToolbarItem(self.window, "drive").view = title
	ns.ToolbarItem(self.window, "drive").bordered = false
	self.toolbarTitle = title
	self.capacity = titleRefs.capacity
	local search = render("ToolbarSearch", {actions = {search = function(value) self.query = value; self:updateRows() end}})
	search.frame = ns.Rect(ns.Point(0, 0), ns.Size(search.fixedWidth, search.fixedHeight))
	ns.ToolbarItem(self.window, "search").view = search
	ns.MenuItem {menu = "Go", title = "Back", keyEquivalent = "[", action = actions.back}
	ns.MenuItem {menu = "Go", title = "Forward", keyEquivalent = "]", action = actions.forward}
	ns.MenuItem {menu = "View", title = "Rescan", keyEquivalent = "r", action = actions.refresh}
	if arg and arg[1] then self:startScan(arg[1])
	else self.scanStatus = "Choose Scan Folder to begin; background checks only inspect known developer caches."
		self:showSection("Disk Map"); self:showDetail(); self:updateToolbar()
	end
	self:updateCapacity()
	self:scanSuggestions()
	ns.async(function()
		while true do
			ns.sleep(30)
			if not self.window.visible then self:cancel(self.scanJob); self:cancel(self.suggestionJob); return end
			self.monitorTicks = (self.monitorTicks or 0) + 1
			if self.monitoring and self.monitorTicks % 30 == 0 then self:scanSuggestions() end
		end
	end)
	return self.window
end
return Controller
