local Model = require("data.model")
local Fixture = require("apps.diskmap.services.Fixture")
local Environment = require("apps.diskmap.controllers.Environment")
local PageController = require("data.pagecontroller")
local ns = require("AppKit")
local Harness = {}

-- A complete environment over the synthetic Mac (services/Fixture.lua)
-- with a recording router and no native window. The sources have run.
function Harness.env(options)
	options = options or {}
	local host = {events = {}}
	local function record(name)
		return function(...) table.insert(host.events, {name = name, args = table.pack(...)}) end
	end
	local router = {destination = function() return host.destination end, show = record("show"), keep = record("keep")}
	router.refresh = function()
		if host.page and host.page.template then host.page:update(host.env:state()) end
	end
	router.changed = router.refresh
	host.service = options.service or Fixture.new({showcase = true})
	host.env = Environment.new(host.service, {isolated = true}, router)
	Model.bind(host.env.model)
	host.env:prepare()
	if options.measure ~= false then host.env.sources:run() end
	return host
end

-- Mounts page `id` into a detached stack; returns the page controller.
function Harness.mount(id, host, params)
	if host.page then host.page:dispose() end
	Model.bind(host.env.model)
	host.destination = id
	local request = host.env:page(id)
	-- The page controller hands lists to native tables, not to `presented`;
	-- the harness keeps the last draw's rows in `host.lists`.
	if not request.harnessed then
		local data = request.data
		request.harnessed = true
		request.data = function(page, state)
			local result = data(page, state)
			host.lists = result.lists or {}
			return result
		end
	end
	if request.focus then request:focus(params or {}) end
	host.page = PageController.new({page = host.env.manifest.pages[id], request = request, ns = ns,
		viewsDir = "apps/diskmap/views/", store = host.env.model, presented = function(data) host.presented = data end})
	host.page:mount(ns.VStack {}, host.env:state())
	return host.page
end

-- The whole app with its window, over the synthetic Mac.
function Harness.app(options)
	local Controller = require("apps.diskmap.Controller")
	local service = (options or {}).service or Fixture.new({showcase = true})
	local app = Controller.new(service, {isolated = (options or {}).isolated, page = (options or {}).page})
	app:createWindow()
	return app, service
end

return Harness
