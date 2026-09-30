-- Where opening a resource goes. Every list, menu and link in Diskmap opens
-- a resource by its own id and asks here; no page decides for itself.
-- The catalog declares the exceptions on the resource: `page` names the
-- sidebar page that presents it and everything under it (Developer projects
-- on Projects, Simulator devices on Simulators, DerivedData on Xcode, every
-- app on Applications), `sheet` its own sheet (the SDKs of an Xcode
-- installation). Everything else opens in its category's list: a group as
-- itself, a location in its group with its row selected.
local Destinations = {}

-- Returns {page = pageId} | {sheet = name, id = id} |
-- {category = groupId, select = leafId or nil}, or nil for an unknown id.
function Destinations.resolve(model, id)
	local resource = model.resources:find(id)
	if not resource then return nil end
	if resource.sheet then return {sheet = resource.sheet, id = id} end
	local row = resource
	while row do
		if row.page then return {page = row.page, id = id} end
		row = row:getParent()
	end
	if not resource:isLeaf() then return {category = id} end
	local parent = resource:getParent()
	return {category = parent and parent.id or id, select = id}
end

-- Whether opening a resource leaves its category's list for a page or sheet
-- of its own; such rows show the "open" button in a category list.
function Destinations.elsewhere(model, id)
	local destination = Destinations.resolve(model, id)
	return destination ~= nil and destination.category == nil
end

return Destinations
