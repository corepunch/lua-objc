local Flow = require("data.flow")
local Keeps = require("apps.diskmap.models.Keeps")
local Verdict = require("apps.diskmap.helpers.Verdict")
local Categories = require("apps.diskmap.models.Categories")
local Remove = require("apps.diskmap.flows.Remove")
local Rows = Flow:extend()

-- Row actions for every list in Diskmap: the remove button, and the row's
-- menu with the same verbs in the same order on every page (Look Inside,
-- Show in Finder, Remove, Keep, Copy Path). A flow (lua/data/flow.lua)
-- over a page: `self:flow("Rows"):menu(row)`.

-- Presents rows for a list: the verdict's symbol, the remove button's
-- state and the share meter, with Keep applied.
function Rows:present(rows, now)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.bytes or 0) end
	local presented = {}
	for _, source in ipairs(rows) do
		local row = {}
		for key, value in pairs(source) do row[key] = value end
		if Keeps:contains(row.id) then row.verdict, row.action, row.reason = "keep", "none", "Marked Keep." end
		Verdict.present(row, now)
		row.relative = row.bytes and largest > 0 and row.bytes / largest or 0
		row.shareText = ""
		-- The symbol wears its source's colour; the meter the verdict's.
		local category = Categories:find(row.category)
		row.levelColor = Verdict.styles[row.verdict] and Verdict.styles[row.verdict].color or "systemGray"
		row.color = category and category.color or "systemGray"
		row.icon = row.icon or (row.directory == false and "doc" or "folder.fill")
		local allowed, why = Remove.allowed(row)
		row.removable = allowed
		row.removeHelp = allowed and (Remove.verbs[row.action or "trash"] .. "…") or why
		row.hasMenu = row.path ~= nil
		table.insert(presented, row)
	end
	return presented
end

-- Removes one row after confirmation.
function Rows:remove(row)
	return self:flow("Remove"):rows({row})
end

-- Removes every row with a safe verdict, after one confirmation.
function Rows:removeSafe(rows)
	local safe = {}
	for _, row in ipairs(rows) do
		if row.verdict == "safe" and Remove.allowed(row) then table.insert(safe, row) end
	end
	if #safe == 0 then return false end
	return self:flow("Remove"):rows(safe)
end

function Rows:menu(row)
	if not row or not row.path then return {} end
	local app, service = self.app, self.app.service
	local items = {}
	if row.state == "measured" and row.directory ~= false then
		table.insert(items, {title = "Look Inside", systemImage = "folder", action = function() app.show("folder", {path = row.path}) end})
	end
	table.insert(items, {title = "Show in Finder", systemImage = "arrow.up.forward.square", action = function() service.reveal(row.path) end})
	if row.settings then
		table.insert(items, {title = "Open System Settings", systemImage = "gearshape", action = function() service.openSettings(row.settings) end})
	end
	local function separator() if items[#items] and not items[#items].separator then table.insert(items, {separator = true}) end end
	separator()
	if Remove.allowed(row) then
		table.insert(items, {title = Remove.verbs[row.action or "trash"] .. "…", systemImage = "trash", action = function() self:remove(row) end})
	end
	if row.id and row.verdict ~= "system" then
		local kept = Keeps:contains(row.id)
		table.insert(items, {title = kept and "Stop Keeping" or "Keep", systemImage = kept and "pin.slash" or "pin", action = function() app.keep(row.id) end})
	end
	separator()
	table.insert(items, {title = "Copy Path", systemImage = "doc.on.doc", action = function() service.copy(row.path) end})
	return items
end

return Rows
