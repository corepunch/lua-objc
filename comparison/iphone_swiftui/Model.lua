local Model = {}

local CONTRACT = "comparison/iphone_swiftui/contract.json"

function Model.load(ns)
	local source = assert(ns._readFile(CONTRACT), "comparison contract is unavailable")
	local contract = ns.json_parse(source)
	assert(contract.schema == 1, "unsupported comparison contract")
	local requested = os.getenv("LUA_OBJC_COMPARISON_FIXTURE") or "labels"
	for _, screen in ipairs(contract.screens) do
		if screen.id == requested then
			screen.contract = contract
			screen.layout = contract.layout
			return screen
		end
	end
	error("unknown comparison fixture: " .. requested)
end

return Model
