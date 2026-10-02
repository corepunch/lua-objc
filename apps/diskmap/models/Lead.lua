-- A page's leading decision, the Record views/DecisionCard.etlua binds
-- (schemas/Decision.xml). `spec` names the fields; `run` and `secondary` are
-- the commands behind the two buttons. A decision without `run` has no
-- enabled primary button.
local Lead = {}

local function nothing() end

function Lead.new(spec)
	spec.shown = true
	spec.runnable = spec.run ~= nil
	spec.run = spec.run or nothing
	spec.secondary = spec.secondary or nothing
	return spec
end

return Lead
