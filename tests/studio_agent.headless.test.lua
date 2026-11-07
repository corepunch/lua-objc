local t = require("TestKit")
local Model = require("data.model")
local Store = require("apps.studio.Store")
local Session = require("apps.studio.services.Session")
local Agent = require("apps.studio.services.Agent")
local Chat = require("apps.studio.controllers.ChatController")
Model.bind(Store())
local seed = { ["demo/playground/init.lua"] = "return {}", ["demo/playground/Model.lua"] = "return {}",
	["demo/playground/Controller.lua"] = "return {}", ["demo/playground/views/Window.etlua"] = '<Label text="Hello" />' }
local storage = { load = function() end, save = function() return true end }
local session = Session.open(storage, seed, "Agent")
local pending, payload, cancellations, renders = nil, nil, 0, 0
local codec = { decode = function(value) return value end, encode = function(value) return value end }
local transport = function(body, key, callback)
	payload, pending = body, callback
	t.assertEqual(key, "test-key", "the credential goes to the transport")
	return function() cancellations = cancellations + 1 end
end
local agent = Agent.new(session, transport, codec, function() renders = renders + 1; return true end, function() end)
t.expect(not agent:send("", "test-key"), "empty prompts are rejected")
t.expect(not agent:send("Hello", ""), "missing keys are rejected")
t.expect(agent:send("Change the model", "test-key"), "a turn starts")
t.expect(not agent:send("again", "test-key"), "concurrent sends are rejected")
t.assertEqual(session.workspace.messages[1].role, "user", "the real user turn is visible")
t.assertEqual(payload.model, "openrouter/free", "the selected model is used")
t.assertEqual(payload.parallel_tool_calls, nil, "free tool providers reject an explicit parallel-tool parameter")
pending({ choices = {{ message = { role = "assistant", tool_calls = {{id = "edit", ["function"] = {
	name = "applyFiles", arguments = {files = {{path = "demo/playground/Model.lua", content = "return { count = 1 }"}}},
}}} }}} })
t.assertEqual(session.workspace.files["demo/playground/Model.lua"], "return { count = 1 }", "the agent saves actual source")
t.assertEqual(renders, 1, "the saved source is previewed")
local toolResult = payload.messages[#payload.messages]
t.assertEqual(toolResult.tool_call_id, "edit", "the result matches its tool call")
t.expect(toolResult.content.result.saved, "the provider receives save success")
t.assertEqual(session.workspace.messages[2].changes[1].path, "Model.lua", "the change card names the edited file")
local finish = pending
finish({ choices = {{ message = { role = "assistant", content = "Done" }}} })
finish({ choices = {{ message = { role = "assistant", content = "Duplicate" }}} })
t.expect(not agent.busy, "a final answer ends the turn")
t.assertEqual(session.workspace.messages[#session.workspace.messages].text, "Done", "duplicate callbacks are ignored")
t.expect(agent:send("Next", "test-key"), "another turn starts")
local late = pending
agent:stop()
t.assertEqual(cancellations, 1, "Stop cancels the active request")
local count = #session.workspace.messages
late({ choices = {{message = {content = "Late"}}} })
t.assertEqual(#session.workspace.messages, count, "a cancelled response cannot change the project")
t.expect(agent:send("Again", "test-key"), "a cancelled session can restart")
pending(nil, "offline")
t.expect(not agent.busy and session.workspace:transcript():find("offline", 1, true), "network errors are visible and release busy state")
agent:send("Again", "test-key")
pending({ choices = {42} })
t.expect(not agent.busy, "malformed provider data cannot leave the agent running")

-- A cached/synchronous response can start the next request before transport
-- returns its old cancel function. Stop must cancel the new request instead.
local calls, cancelled = 0, nil
local immediate = Agent.new(session, function(_, _, callback)
	calls = calls + 1
	local index = calls
	if index == 1 then callback({ choices = {{ message = {tool_calls = {{id = "files", ["function"] = {
		name = "listFiles", arguments = {},
	}}}}}} }) end
	return function() cancelled = index end
end, codec, function() return true end, function() end)
immediate:send("Inspect", "test-key")
immediate:stop()
t.assertEqual(cancelled, 2, "synchronous callbacks cannot overwrite the active cancellation")
local broken = Agent.new(session, function() error("transport failed") end, codec, function() end, function() end)
t.expect(broken:send("Inspect", "test-key"), "transport exceptions are handled by the agent")
t.expect(not broken.busy and session.workspace:transcript():find("transport failed", 1, true), "transport exceptions are visible")

local chat = Chat.new()
chat:attach(session, { transport = transport, json = codec, credentials = { read = function() return "test-key" end } },
	function() return true end, function() end)
chat.draft = "A real request"
t.expect(chat:send(), "the composer dispatches the actual draft")
t.assertEqual(chat.draft, "", "a dispatched draft is cleared")
chat:stop()
t.expect(not chat.agent.busy, "the composer can stop the request")
local event, started, stopped = nil, 0, 0
chat.device.speech = {recognizer = function(callback)
	event = callback
	return {start = function() started = started + 1 end, stop = function() stopped = stopped + 1 end, cancel = function() end}
end}
chat.draft = "Please"
t.expect(chat:toggleDictation(), "dictation starts through the injected speech service")
t.assertEqual(started, 1, "the microphone starts only on request")
event("partial", "change the screen")
t.assertEqual(chat.draft, "Please change the screen", "partial dictation extends the typed draft")
chat:toggleDictation(); t.assertEqual(stopped, 1, "another microphone press stops recording")
event("finished", "change the screen")
t.expect(not chat.listening, "finished speech releases listening state")
t.expect(chat:attachFiles({{name="notes.txt",text="Use a native button"}}), "text context can be attached")
t.expect(not chat:attachFiles({{name="large.txt",text=string.rep("x",128*1024+1)}}), "oversized context is rejected")
t.assertEqual(#chat.attachments, 1, "rejected attachments do not change the draft")
t.expect(chat:send(), "a dictated request with context sends")
t.expect(payload.messages[#payload.messages].content:find("Use a native button",1,true), "attached text is sent as request context")
t.assertEqual(#chat.attachments, 0, "sent attachments are cleared")
chat:stop()
agent:send("Malformed tool", "test-key")
pending({choices={{message={tool_calls={42}}}}})
t.expect(not agent.busy, "malformed tool entries end with a visible error")
local diff = require("apps.studio.helpers.Changes")
local fresh = diff.between({}, {["demo/playground/New.lua"]="return 1\n"})[1]
t.assertEqual(fresh.added,1,"a new file counts its actual source lines")
t.assertEqual(fresh.removed,0,"a new file has no removed blank line")
t.assertEqual(#diff.between({x="same\n"},{x="same\n"}),0,"unchanged source has no change card")
os.exit(t.summary() and 0 or 1)
