-- A Diskmap page on its own, without the root: the framework's page controller
-- over one model of apps/diskmap/models, with the services a test supplies.
-- `refresh` draws the mounted page again, as the root does when work that
-- started earlier finishes. Returns the controller and the model it draws.
local Define = require("data.model")
local PageController = require("data.pagecontroller")
local ns = require("AppKit")
local Host = {}

function Host.new(id, class, view, services)
	local controller
	local context = {rescan = function() end, log = function() end, show = function() end,
		refresh = function() if controller.template then controller:update(controller.state) end end}
	for key, value in pairs(services) do context[key] = value end
	local graph = Define.graph({classes = {[id] = function() return require("apps.diskmap.models." .. class) end}, services = context})
	controller = PageController.new({page = {id = id, title = id, icon = "circle", color = "systemBlue", model = id, view = view},
		graph = graph, ns = ns, viewsDir = "apps/diskmap/views/"})
	return controller, graph:build({id})[id]
end

return Host
