local Model = require("data.model")
local Mock = require("apps.diskmap.services.Mock")
local Environment = require("apps.diskmap.controllers.Environment")
local PageController = require("data.pagecontroller")
local ns = require("AppKit")
local Harness = {}

-- A complete environment with a recording router and no native window.
-- Providers deliver into the environment's bound store, even when two
-- environments' deferred callbacks are interleaved.
function Harness.env(options)
	options = options or {}
	local host = {events = {}}
	local function record(name)
		return function(...) table.insert(host.events, {name = name, args = table.pack(...)}) end
	end
	local router = {shortcuts = function() return {} end, destination = function() return host.destination end,
		links = {}, command = record("command"), open = record("open"), show = record("show"), search = record("search"),
		openReview = record("review"), openHistory = record("history"), access = record("access"), openChanges = record("changes"),
		onboarded = record("onboarded"), keep = record("keep")}
	router.refresh = function()
		if host.page and host.page.template then host.page:update(host.env:state()) end
	end
	router.awaitAccess = function() end
	router.changed = router.refresh
	router.basketChanged = function() if host.page then host.page:marksChanged() end end
	host.service = options.service or Mock.new({showcase = true, deferred = options.deferred})
	host.env = Environment.new(host.service, {isolated = true}, router)
	Model.bind(host.env.model)
	host.env:prepare()
	host.env.scan:start()
	host.service.settle()
	return host
end

function Harness.mount(id, host, params)
	if host.page then host.page:dispose() end
	Model.bind(host.env.model)
	host.destination = id
	local request = host.env:page(id)
	if request.focus then request:focus(params or {}) end
	host.page = PageController.new({page = host.env.manifest.pages[id], request = request, ns = ns,
		viewsDir = "apps/diskmap/views/", store = host.env.model})
	host.page:mount(ns.VStack {}, host.env:state())
	return host.page
end

return Harness
