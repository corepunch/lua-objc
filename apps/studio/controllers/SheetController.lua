local xml = require("ui.xml")
local Template = require("ui.template")
local Sheet = {}
Sheet.__index = Sheet
function Sheet.new(ns)
	return setmetatable({ns = ns}, Sheet)
end
function Sheet:present(view, data)
	-- Catalog → creation is a change of sheet content. Keep UIKit's existing
	-- presentation instead of presenting from a controller being dismissed.
	if self.template and not self.template.closed then
		self.template.path = "apps/studio/views/sheets/" .. view .. ".etlua"
		self.template:update(data)
		return
	end
	local popup = view == "Settings"
	self.ns.presentSheet(function()
		local shell = view == "Settings" and "SettingsShell" or "Shell"
		local native, refs = xml.renderFile("apps/studio/views/sheets/" .. shell .. ".etlua", {actions = data.actions}, self.ns)
		self.template = Template.new(refs.content, "apps/studio/views/sheets/" .. view .. ".etlua", self.ns)
		self.template:update(data)
		return native
	end, {title = data.title, presentationStyle = popup and "formSheet" or "pageSheet",
		detents = not popup and {"large"} or nil, dragIndicator = not popup})
end
function Sheet:update(data)
	if self.template and not self.template.closed then self.template:update(data) end
end
function Sheet:close()
	if self.template and not self.template.closed then self.ns.dismiss() end
	self.template = nil
end
return Sheet
