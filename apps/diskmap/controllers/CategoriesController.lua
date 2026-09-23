local Categories = require("apps.diskmap.models.Categories")
local Model = require("apps.diskmap.Model")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, navigate)
	return setmetatable({model = model, navigate = navigate}, Controller)
end
function Controller:rows(root, query) return Categories.rows(self.model, root, query) end
function Controller:bar(disk)
	local segments, explanation = Categories.distribution(self.model, disk)
	local actions = {}
	for _, segment in ipairs(segments) do
		actions["category_" .. segment.id] = function() self.navigate(segment.id) end
	end
	return {segments = segments, explanation = explanation, actions = actions}
end
function Controller:capacity(disk)
	if not disk then return "Capacity unavailable" end
	return Model.size(disk.totalKb * 1024) .. " total  ·  " .. Model.size((disk.totalKb - disk.freeKb) * 1024) .. " used  ·  " .. Model.size(disk.freeKb * 1024) .. " available"
end
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
