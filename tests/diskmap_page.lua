-- A Diskmap page on its own, without the root: the framework's page controller
-- over the page one route of apps/diskmap/routes.lua builds, with the services
-- a test supplies. `services.model` is the store the page's models read.
-- `refresh` draws the mounted page again, as the root does when work that
-- started earlier finishes. Returns the controller and the page it draws.
local Model = require("data.model")
local Routes = require("data.routes")
local PageController = require("data.pagecontroller")
local ns = require("AppKit")
local Host = {}

-- `params` are the page's app.xml attributes (`{workflow = "music"}`).
function Host.new(id, services, params)
	local controller
	local context = {rescan = function() end, removed = function() end, trashed = function() end, remeasure = function() end,
		log = function() end, show = function() end,
		refresh = function() if controller.template then controller:update(controller.state) end end}
	for key, value in pairs(services) do context[key] = value end
	if not pcall(require("apps.diskmap.services.Contract").check, context.service) then
		context.service = require("apps.diskmap.services.Contract").stub(context.service)
	end
	if context.model then Model.bind(context.model) end
	context.inventories = context.inventories or require("apps.diskmap.services.Inventories").new(context.service, context.refresh, function() return 0 end)
	context.basketChanged = context.basketChanged or context.refresh
	if not context.basket then
		context.basket = require("apps.diskmap.flows.Basket")({app = context})
		context.basket.results, context.basket.done = {}, {}
	end
	local entry = {id = id, title = id, icon = "circle", color = "systemBlue", attrs = params or {}}
	local page = Routes.page(Routes.find(require("apps.diskmap.routes"), entry), entry, context, "apps.diskmap")
	controller = PageController.new({page = entry, request = page, ns = ns, viewsDir = "apps/diskmap/views/", store = context.model})
	return controller, page
end

return Host
