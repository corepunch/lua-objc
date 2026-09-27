local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Duplicates = require("apps.diskmap.models.Duplicates")
local Controller = {}; Controller.__index = Controller

-- The Duplicates page. Reading contents is a privacy boundary, so nothing
-- is read until the person adds a folder and starts a search, and only
-- that folder is read. Results last for the session.
function Controller.new(model, service, actions)
	local load = rawget(service, "loadFolders")
	return setmetatable({model = model, service = service, actions = actions,
		roots = load and load("duplicates") or {}}, Controller)
end

local function display(path, home)
	if home and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
	return path
end

function Controller:rootsText()
	if #self.roots == 0 then return "Add the folders to compare. Diskmap reads file contents only in them." end
	local names = {}
	for _, root in ipairs(self.roots) do table.insert(names, display(root, self.model.home)) end
	return "Comparing files in " .. table.concat(names, ", ") .. "."
end

function Controller:mount(host, state)
	self.query = state.query or ""
	self.template = Template.new(host, "apps/diskmap/views/Duplicates.etlua", ns)
	local _, refs = self.template:update({roots = self:rootsText(), actions = {
		addFolder = function() self:addFolder() end,
		search = function() if self.job then self:stop() else self:search() end end,
		menu = function(_, _, row) return self:menu(row) end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self.refs = refs
	self:show()
	return refs
end

function Controller:addFolder()
	local pick = rawget(self.service, "pickFolder")
	local path = pick and pick("Choose a Folder to Compare")
	if not path then return end
	for _, root in ipairs(self.roots) do if root == path then return end end
	table.insert(self.roots, path)
	local save = rawget(self.service, "saveFolders")
	if save then save("duplicates", self.roots) end
	self.result = nil
	self:show()
end

function Controller:search()
	if #self.roots == 0 then return end
	self.result, self.progress = nil, {examined = 0}
	self.job = self.service.findDuplicates(self.roots, function(result)
		self.job, self.result, self.progress = nil, result, nil
		self:show()
	end, function(progress) self.progress = progress; self:show() end)
	self:show()
end

function Controller:stop()
	if self.job then self.job.cancel() end
	self.job, self.progress = nil, nil
	self:show()
end

function Controller:menu(row)
	local items, keep = Duplicates.copies(row.group)
	local menu = {{title = "Mark " .. #items .. (#items == 1 and " Copy" or " Copies") .. " for Cleanup", systemImage = "plus.circle",
		action = function() self.actions:markAll(items) end}}
	table.insert(menu, {title = "Show Kept Copy", systemImage = "folder", action = function() self.service.reveal(keep.path) end})
	for _, item in ipairs(items) do
		table.insert(menu, {title = "Show " .. display(item.path, self.model.home), systemImage = "doc",
			action = function() self.service.reveal(item.path) end})
	end
	return menu
end

function Controller:show()
	if not self.refs then return end
	local refs = self.refs
	refs.addFolder.enabled = not self.job
	refs.search.title = self.job and "Stop" or "Find Duplicates"
	refs.search.enabled = #self.roots > 0
	refs.duplicateRoots.text = self:rootsText()
	local groups = self.result and self.result.groups or {}
	local rows = self.actions:annotate(Duplicates.rows(groups, self.query, self.model.home))
	refs.duplicates:replaceRows(rows)
	local summary = Duplicates.summary(groups)
	refs.duplicatesList.hidden = #rows == 0
	refs.duplicatesEmpty.hidden = #rows > 0
	refs.duplicatesSummary.text = self.job and string.format("Comparing… %s files examined", Model.count(self.progress and self.progress.examined or 0))
		or not self.result and "Identical files in folders you choose."
		or summary.groups == 0 and "No identical files found."
		or string.format("%d %s could free %s", summary.copies, summary.copies == 1 and "copy" or "copies", Model.size(summary.bytes))
end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

function Controller:marksChanged() self:show() end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
