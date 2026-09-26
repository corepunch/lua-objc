local Categories = require("apps.diskmap.models.Categories")
local Model = require("apps.diskmap.Model")
local Controller = {}; Controller.__index = Controller
function Controller.new(model)
	return setmetatable({model = model}, Controller)
end
function Controller:rows(root, query) return Categories.rows(self.model, root, query) end
function Controller:coverage(disk)
	local measured = Model.total(self.model)
	local partial = (self.model.scan.errors or 0) > 0
	local text = (partial and "At least " or "") .. Model.size(measured) .. " measured"
	if partial then text = text .. string.format(" · %d filesystem read issues", self.model.scan.errors) end
	if disk then
		local difference = (disk.totalKb - disk.freeKb) * 1024 - measured
		text = text .. " · " .. (difference < 0 and "−" or "") .. Model.size(math.abs(difference)) .. " not attributed"
	end
	return text
end
return Controller
