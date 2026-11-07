local Model = require("data.model")
local Counters, Counter = Model:extend("starterCounters", {primaryKey = "id"})
function Counter:increment()
	return self:update({ value = self.value + 1 })
end
return Counters
