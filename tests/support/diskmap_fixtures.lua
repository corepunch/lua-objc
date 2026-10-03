local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Harness = require("tests.support.diskmap")
local xml = require("ui.xml")
local ns = require("AppKit")
local Fixtures = {}; Fixtures.__index = Fixtures

-- Child previews use the same presentation queries and real route actions as
-- the app. A single finished environment supplies every fixture in a test.
function Fixtures.new()
	return setmetatable({host = Harness.env()}, Fixtures)
end

function Fixtures:get(name)
	local env = self.host.env
	Model.bind(env.model)
	local request, view, data, all
	if name == "hero" or name == "notMeasured" then
		request = env:page("overview"); all = request:data(env:state())
		view = name == "hero" and "sections/Hero" or "sections/NotMeasured"
		data = name == "hero" and all.hero or all.unmeasured
	elseif name == "decision" or name == "tips" then
		request = env:page("cleanup"); all = request:data(env:state())
		view = name == "decision" and "sections/Decision" or "sections/Tips"
		data = name == "decision" and all.children.lead or all.children.tips
	elseif name == "kinds" then
		request = env:page("kinds"); data = request:data(env:state()); view = request.view
		data.page = env.manifest.pages.kinds
	elseif name == "changes" then
		request = env.session.changesSheet
		local before = Locations:totals()
		for id, bytes in pairs(before) do before[id] = math.floor(bytes / 2) end
		request.result = Locations:changesSince({createdAt = os.time({year = 2026, month = 9, day = 1, hour = 12}), totals = before})
		data, view = request:data(), request.view
	elseif name == "settings" then
		request = env.settings; data, view = request:data(), request.view
	else error("Unknown Diskmap fixture: " .. tostring(name), 2) end
	local handlers = all and all.handlers or data.handlers
	data.actions = setmetatable({}, {__index = function(_, action)
		local method = request[action] or handlers and handlers[action]
		if type(method) ~= "function" then return nil end
		return Model.bound(env.model, function(...) return method(request, ...) end)
	end})
	data.overrides = {texts = data.texts, hidden = data.hidden, disabled = data.disabled}
	return {view = "apps/diskmap/views/" .. view .. ".etlua", data = data, request = request}
end

function Fixtures:render(name)
	local fixture = self:get(name)
	local view, refs = xml.renderFile(fixture.view, fixture.data, ns)
	for id, rows in pairs(fixture.data.lists or {}) do refs[id]:replaceRows(rows) end
	if name == "settings" then fixture.request:sync(refs) end
	return view, refs
end

function Fixtures:dispose() self.host.env:dispose() end

return Fixtures
