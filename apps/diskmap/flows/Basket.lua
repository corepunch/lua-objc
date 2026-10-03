local Model = require("data.model")
local Flow = require("data.flow")
local Marks = require("apps.diskmap.models.Marks")
local Paths = require("apps.diskmap.helpers.Paths")
local Basket = Flow:extend()

function Basket:isMarked(path) return path ~= nil and Marks:contains(path) end
function Basket:covering(path) return Marks:covering(path) end
function Basket:summary() return Marks:summary() end
function Basket:count() return Marks:count() end

-- Identity and basket validation are identical for individual and bulk
-- staging. Only the caller publishes, so a bulk click refreshes UI once.
local function add(self, item)
	local valid, why = Paths.validate(item.path, Model.db.home)
	if not valid then return false, why end
	local identity = self.app.service.fileIdentity
	if not item.identity then item.identity = identity(item.path) end
	local ok, reason = Marks:add(item)
	if ok then
		self.results[item.path] = nil
		self.done[item.path] = nil
	end
	return ok, reason
end

-- Marks or unmarks an item {path, name, bytes, consequence, source,
-- resourceId}. Returns marked state and a refusal message.
function Basket:toggle(item)
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

function Basket:markAll(items)
	local count, refused = 0, {}
	for _, item in ipairs(items) do
		if type(item) == "table" and item.path and not self:covering(item.path) then
			local ok, reason = add(self, item)
			if ok then count = count + 1 else table.insert(refused, (item.name or item.path) .. ": " .. tostring(reason)) end
		end
	end
	if #refused > 0 then self.app.service.showError("Some items were not marked", table.concat(refused, "\n")) end
	if count > 0 then self.app.basketChanged() end
	return count
end

function Basket:removeAll(items)
	for _, item in ipairs(items) do Marks:remove(item.path) end
	self.app.basketChanged()
end

return Basket
