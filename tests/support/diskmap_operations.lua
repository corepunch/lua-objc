local Model = require("data.model")
local Operations = require("apps.diskmap.helpers.Operations")
return function(host, id)
	local items = host.operations
	if not items then
		Model.bind(host.context.store)
		items = Operations.forPage(host.page.id, host.request:data(host.state))
	end
	for _, item in ipairs(items) do
		if item.id == id then return {enabled = not item.disabled, hidden = item.hidden, title = item.title, action = item.action} end
	end
	error("missing page operation " .. id)
end
