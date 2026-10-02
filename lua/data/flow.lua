-- Flows: Lapis' Flow, a piece of action code shared by several pages.
--
-- A flow wraps an object (a page, or the app's services) and forwards to it
-- every field the flow does not define, so its methods read like the
-- page's own: `self.app`, `self.params`, the page's methods. What a flow
-- assigns stays on the flow, unless the flow class sets `exposeAssigns`:
-- then it is the page's (Lapis' expose_assigns).
--
--   local Flow = require("data.flow")
--   local Marks = Flow:extend()
--
--   function Marks:markAll(rows)
--   	for _, row in ipairs(rows) do self.app.review:toggle(row) end
--   end
--
--   -- in a route
--   markFiles = function(self) Marks(self):markAll(self.visible) end
local Flow = {}

-- A new flow class; `methods` (optional) are its methods.
function Flow:extend(methods)
	local class = methods or {}
	local meta = {__index = function(flow, key)
		local value = class[key]
		if value ~= nil then return value end
		local target = rawget(flow, "_")
		value = target[key]
		-- A method of the target runs on the target, not on the flow.
		if type(value) == "function" then
			local method = value
			value = function(caller, ...)
				if caller == flow then caller = target end
				return method(caller, ...)
			end
			rawset(flow, key, value)
		end
		return value
	end, __newindex = function(flow, key, value)
		if class.exposeAssigns then rawget(flow, "_")[key] = value else rawset(flow, key, value) end
	end, flow = true}
	return setmetatable(class, {__call = function(_, target)
		assert(type(target) == "table", "a flow wraps a table")
		-- A flow of a flow wraps the same target.
		if getmetatable(target) and getmetatable(target).flow then target = rawget(target, "_") end
		return setmetatable({_ = target}, meta)
	end, __index = self})
end

return Flow
