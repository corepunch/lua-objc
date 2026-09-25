local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local Controller = {}; Controller.__index = Controller

-- Suggested cleanups sheet. The cleanup and tips controllers own the data;
-- this controller owns the sheet, its search query, and the two retained
-- template mounts inside it.
function Controller.new(cleanup, tips, disk)
	return setmetatable({cleanup = cleanup, tips = tips, disk = disk, query = ""}, Controller)
end

function Controller:update()
	if not self.opportunities then return end
	self.opportunities:update(self.cleanup:presentation(self.query))
	self.tipPanel:update(self.tips:presentation(self.disk()))
end

function Controller:open(parent)
	self:close()
	self.query = ""
	self.sheet, self.refs = ns.presentSheet(function()
		local sheet, refs = xml.renderFile("apps/diskmap/views/Reclaim.etlua", {actions = {
			search = function(value) self.query = value or ""; self:update() end,
			done = function() self:close() end,
		}}, ns)
		self.opportunities = Template.new(refs.opportunities, "apps/diskmap/views/Opportunities.etlua", ns)
		self.tipPanel = Template.new(refs.tips, "apps/diskmap/views/Tips.etlua", ns)
		self:update()
		return sheet, refs
	end, {parent = parent})
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs, self.opportunities, self.tipPanel = nil, nil, nil, nil
end

return Controller
