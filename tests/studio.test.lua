_G.__headless = true
local t = require("TestKit")
local Model = require("apps.studio.Model")
local Agent = require("apps.studio.services.Agent")
local Preview = require("apps.studio.services.Preview")
local ns = require("AppKit")
local function read(path)
	local file = assert(io.open(path)); local value = file:read("*a"); file:close(); return value
end
local seed = {}
for _, name in ipairs({ "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }) do
	seed["apps/playground/" .. name] = read("apps/playground/" .. name)
end
local saved, failSave
local storage = { load = function() return nil end, save = function(value)
	if failSave then return nil, "disk full" end
	saved = value; return true
end }
local model = Model.new(storage, seed)
t.assertEqual(model.model, "openrouter/free", "new workspaces start with OpenRouter free router")
t.assertEqual(#model:listFiles(), 4, "starter has four MVC files")
for _, path in ipairs({ "../secret.lua", "/tmp/file.lua", "apps/playground/../studio/Model.lua", "apps/playground//a.lua", "apps/playground/evil.txt", "apps/playground/a\\b.lua" }) do
	t.expect(not Model.validPath(path), "reject unsafe path " .. path)
end
local path = "apps/playground/Model.lua"
local original = model.files[path]
local ok = model:apply({ { path = path, content = "invalid lua !" } })
t.expect(not ok, "invalid Lua rejected")
t.assertEqual(model.files[path], original, "failed edits preserve project")
ok = model:apply({ { path = path, content = "return {}" }, { path = path, content = "return {}" } })
t.expect(not ok, "duplicate edits rejected")
ok = model:apply({ { path = path, content = "return {}" }, { path = "apps/playground/views/Broken.etlua", content = "<% if %>" } })
t.expect(not ok, "template syntax error rejects whole batch")
t.assertEqual(model.files[path], original, "atomic syntax validation")
failSave = true
ok = model:apply({ { path = path, content = "return {}" } })
t.expect(not ok, "write failure is surfaced")
t.assertEqual(#model.history, 0, "failed persistence does not create undo history")
failSave = false
t.expect(model:apply({ { path = path, content = "return {}" } }), "valid edits save")
t.assertEqual(saved.files[path], "return {}", "changes persist")
t.assertEqual(model.files["apps/playground/init.lua"], seed["apps/playground/init.lua"], "unrelated file unchanged")
t.expect(model:undo(), "undo succeeds")
t.assertEqual(model.files[path], original, "undo restores original")
t.expect(not model:undo(), "empty undo is safe")
t.expect(not model:setModel("no-provider"), "model ID validation")
t.expect(model:setModel("provider/test-model"), "custom model allowed")
local restored = Model.new({ load = function() return saved end, save = storage.save }, seed)
t.assertEqual(restored.model, "provider/test-model", "model setting restored")

local pending, payload, cancelled, reloads = nil, nil, 0, 0
local encoded
local agent = Agent.new(model, function(body, key, callback)
	payload, pending = body, callback
	t.assertEqual(key, "test-key", "credential passed to transport only")
	return function() cancelled = cancelled + 1 end
end, { decode = ns.json_parse, encode = function(value) encoded = value; return "tool result" end },
	function() reloads = reloads + 1; return true end, function() end)
t.expect(not agent:send("", "test-key"), "empty prompt rejected")
t.expect(not agent:send("hello", ""), "missing key rejected")
t.expect(agent:send("Change my app", "test-key"), "agent starts")
t.expect(not agent:send("again", "test-key"), "concurrent sends rejected")
t.assertEqual(payload.model, "provider/test-model", "configured model used")
t.assertEqual(#payload.tools, 4, "tools sent with request")
pending({ choices = { { message = { role = "assistant", tool_calls = {
	{ id = "call-1", ["function"] = { name = "readFile", arguments = '{"path":"apps/playground/Model.lua"}' } },
} } } } })
t.assertEqual(encoded.result, original, "readFile returns actual source")
t.assertEqual(payload.messages[#payload.messages].tool_call_id, "call-1", "tool result tied to call")
t.assertEqual(#payload.tools, 4, "tools included on follow-up")
pending({ choices = { { message = { role = "assistant", content = "Done" } } } })
t.expect(not agent.busy, "agent finishes after final answer")
t.expect(agent:send("Try again", "test-key"), "next turn starts")
local late = pending
agent:stop()
t.assertEqual(cancelled, 1, "stop cancels HTTP request")
local messages = #model.messages
late({ choices = { { message = { role = "assistant", content = "late" } } } })
t.assertEqual(#model.messages, messages, "late response ignored")
t.expect(agent:send("Try again", "test-key"), "restart after cancellation")
pending(nil, "offline")
t.expect(not agent.busy, "network errors clear busy state")
t.expect(model:transcript():find("offline", 1, true) ~= nil, "network error visible")
local result = agent:execute({ ["function"] = { name = "applyFiles", arguments = '{"files":[{"path":"apps/playground/Model.lua","content":"return {}"}]}' } })
t.expect(result.saved, "tool applies files")
t.assertEqual(reloads, 1, "tool reloads preview")
model:undo()
local previewNS = {}
for k, v in pairs(ns) do previewNS[k] = v end
previewNS.HostingController = function(view) return view end
local preview = Preview.new(previewNS, read)
local view, err = preview:render(model.files)
t.expect(view ~= nil, "starter renders in isolated preview: " .. tostring(err))
local broken = {}; for k, v in pairs(model.files) do broken[k] = v end
broken[path] = 'error("preview failure")'
view, err = preview:render(broken)
t.expect(not view and err:find("preview failure", 1, true), "runtime error captured")
t.expect(preview:render(model.files) ~= nil, "preview recovers after runtime error")
broken[path] = 'while true do end'
view, err = preview:render(broken)
t.expect(not view and err:find("execution budget", 1, true), "runaway initial render interrupted")
t.expect(preview:render(model.files) ~= nil, "hook restored after budget error")
-- Inspect the current three-column editor template without constructing native UI.
local sidebarPresentation = require("apps.studio.models.Sidebar").presentation()
sidebarPresentation.metrics = {
	iconSize = 20, iconSlotWidth = 32, rowPadding = 8,
	expandedPadding = 12, collapsedPadding = 8,
	expandedWidth = 208, compactWidth = 184, collapsedWidth = 64,
}
sidebarPresentation.collapsed = false
local description = require("ui.xml").describeFile("apps/studio/views/Window.etlua", {
	sidebar = sidebarPresentation,
	preview = { device = "iPhone 16", zoom = "100%", runLabel = "Run" },
	chat = { tabs = { "Preview", "Logs" }, status = "Ready", prompt = "Prompt",
		response = "Response", files = { "App.lua" }, suggestions = {} },
})
t.expect(description.source:find("HabitPal", 1, true) ~= nil, "project navigation renders")
t.expect(description.source:find("hammer.fill", 1, true) ~= nil, "Lua Studio identity keeps its hammer icon")
t.expect(description.source:find("minWidth=\"300\"", 1, true) ~= nil, "preview keeps a usable minimum width")
t.expect(description.source:find("minWidth=\"330\"", 1, true) ~= nil, "chat keeps a usable minimum width")
t.expect(description.source:find("toggleChat", 1, true) ~= nil, "chat visibility customization remains available")
t.expect(description.source:find("toggleSidebarWidth", 1, true) ~= nil, "sidebar width customization remains available")
os.exit(t.summary() and 0 or 1)
