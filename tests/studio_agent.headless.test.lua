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
-- A complete-looking tool call in a truncated response is still untrusted.
local savedRevision = session.workspace.revision
local edit = {id="partial", ["function"]={name="applyFiles",arguments={files={{path="demo/playground/Model.lua",content="return {partial=true}"}}}}}
for _, sample in ipairs({
	{finish_reason="length",message={content="Starting",tool_calls={edit}},text="token limit"},
	{finish_reason="content_filter",message={content=""},text="declined"},
	{finish_reason="error",error={message="provider unavailable"},message={},text="provider unavailable"},
	{finish_reason="stop",message={content="  "},text="empty response"},
	{message={tool_calls="invalid"},text="invalid tool calls"},
	{message={tool_calls={unexpected=edit}},text="invalid tool calls"},
	{message={tool_calls={edit,{id="",["function"]={name="listFiles",arguments={}}}}},text="tool call ID"},
	{message={tool_calls={edit,edit}},text="tool call ID"},
}) do
	agent:send("Handle provider failure", "test-key")
	pending({choices={sample}})
	t.expect(not agent.busy, "invalid provider responses release the busy state")
	local last = session.workspace.messages[#session.workspace.messages]
	t.expect(last.role == "error" and last.text:find(sample.text,1,true), "provider failure explains " .. sample.text)
	t.assertEqual(session.workspace.revision,savedRevision,"rejected envelopes cannot apply even a preceding valid edit")
end
agent:send("Valid response", "test-key")
pending({choices={{finish_reason="stop",message={content="Done",refusal=""}}}})
t.assertEqual(session.workspace.messages[#session.workspace.messages].text,"Done","an empty refusal field does not reject a normal answer")
local guide = agent:execute({["function"]={name="readDocumentation",arguments={topic="controls"}}})
t.expect(guide:find("onChange",1,true) and guide:find("ZERO-BASED",1,true),"the agent can discover actual event and picker contracts")
local modelGuide = agent:execute({["function"]={name="readDocumentation",arguments={topic="models"}}})
t.expect(modelGuide:find("IDs are NOT generated automatically",1,true),"model documentation prevents invented persistence behavior")
local invalidGuide = agent:execute({["function"]={name="readDocumentation",arguments={topic="../secret"}}})
t.expect(invalidGuide.error:find("Choose controls",1,true),"documentation is a closed topic vocabulary, never arbitrary file access")
local badFiles = agent:execute({["function"]={name="applyFiles",arguments={files="[]"}}})
t.expect(badFiles.error:find("not a JSON-encoded string",1,true),"the free router gets actionable schema correction")
t.assertEqual(session.workspace.revision,savedRevision,"malformed file arguments never mutate source")
local failingPreview = Agent.new(session,transport,codec,function() return nil,"Unknown tag <Input>" end,function() end)
local result = failingPreview:execute(edit)
local savedMessage = session.workspace.messages[#session.workspace.messages]
t.assertEqual(result.preview,"error","a runtime failure is returned for repair")
t.assertEqual(savedMessage.previewState,"error","saved changes retain the failed preview outcome")
t.assertEqual(savedMessage.previewError,"Unknown tag <Input>","the actual preview diagnostic is retained")
t.assertEqual(savedMessage.changes[1].path,"Model.lua","the failed preview still shows the actual saved diff")
local success = agent:execute({["function"]={name="applyFiles",arguments={files={{path="demo/playground/Model.lua",content="return {repaired=true}"}}}}})
t.assertEqual(success.preview,"ready","a repaired edit reports success")
t.assertEqual(session.workspace.messages[#session.workspace.messages].previewState,"ready","success is explicit on its own change card")
local interaction
local interactive=Agent.new(session,transport,codec,function() return true end,function() end,function(name,value)
	interaction={name=name,value=value}
	if name=="broken" then return nil,"missing row handler" end
	return {remaining=4}
end)
local tested=interactive:execute({["function"]={name="testAction",arguments={action="toggle_1",state=false}}})
t.assertEqual(interaction.name,"toggle_1","testAction targets the named preview callback")
t.assertEqual(interaction.value,false,"the tool preserves a false boolean argument")
t.assertEqual(tested.data.remaining,4,"the tool returns bounded preview data")
tested=interactive:execute({["function"]={name="testAction",arguments={action="broken"}}})
t.assertEqual(tested.error,"missing row handler","preview interaction errors reach the model for repair")
tested=interactive:execute({["function"]={name="testAction",arguments={action="edit",text="draft",state=true}}})
t.expect(tested.error:find("only one",1,true),"ambiguous event arguments are rejected")
local turns=0
local continuedMessages
local bounded=Agent.new(session,function(body,_,callback)
	turns=turns+1
	if turns>24 then continuedMessages=#body.messages; callback({choices={{message={content="Continued"}}}}); return end
	callback({choices={{message={tool_calls={{id="read_"..turns,["function"]={name="listFiles",arguments={}}}}}}}})
end,codec,function() return true end,function() end)
bounded:send("Keep inspecting","test-key")
t.assertEqual(turns,24,"there is room for reads, edits and interaction checks while keeping a hard limit")
t.expect(not bounded.busy and session.workspace.messages[#session.workspace.messages].text:find("24 agent steps",1,true),"the step limit releases busy state and explains how to continue")
local priorMessages=#bounded.conversation
bounded:send("Continue","test-key")
t.assertEqual(continuedMessages,priorMessages+1,"continuing after a clean step limit retains the completed tool history")
t.expect(not bounded.busy,"continuation finishes normally")
agent:send("Keep my original request", "test-key")
pending({choices={{message={tool_calls={{id="inspect-retry",["function"]={name="listFiles",arguments={project="playground"}}}}}}}})
local completed=#agent.conversation
pending(nil,"provider unavailable")
t.expect(not agent.busy,"provider failure releases busy state")
t.assertEqual(#agent.conversation,completed,"a failed request retains all completed tool exchanges")
agent:send("Try again", "test-key")
t.assertEqual(#payload.messages,completed+1,"a manual retry includes the original request and completed context")
t.expect(payload.messages[completed-2].content=="Keep my original request","the original user intent survives recovery")
pending({choices={{message={content="Recovered"}}}})
t.expect(not agent.busy,"a retry can complete normally")
local encodingFailure=Agent.new(session,transport,{decode=codec.decode,encode=function() error("unsupported snapshot") end},
	function() return true end,function() end)
encodingFailure:send("Inspect safely","test-key")
pending({choices={{message={tool_calls={{id="bad-result",["function"]={name="listFiles",arguments={}}}}}}}})
t.expect(not encodingFailure.busy,"an encoding failure cannot leave the agent working forever")
t.expect(session.workspace.messages[#session.workspace.messages].text:find("Could not encode tool result",1,true),"encoding failures are visible")
t.assertEqual(encodingFailure.conversation[#encodingFailure.conversation].role,"user","a partial tool exchange is removed before retry")
agent:send("Stop explicitly", "test-key"); agent:stop()
t.assertEqual(#agent.conversation,1,"explicit Stop still starts a clean conversation")
-- A project's AGENTS.md is the one non-code file the agent may edit; other
-- text files stay out, and the readKit tool serves a kit's manifest.
t.expect(session:apply({{path = "demo/playground/AGENTS.md", content = "# Rules"}}), "AGENTS.md saves without a syntax check")
t.expect(not session:apply({{path = "demo/playground/notes.md", content = "notes"}}), "other markdown files are refused")
local Api = require("apps.studio.helpers.Api")
local manifest = Api.kit("platformer-kit", function(path) local f = io.open(path, "rb"); local s = f and f:read("a"); if f then f:close() end; return s end)
t.expect(manifest and manifest:find('"coin%-gold"'), "readKit returns a kit's manifest")
t.expect(not Api.kit("../secrets", function() return "x" end), "readKit takes only kit names")
t.expect(Api.read("games"):find("readKit"), "the games guide points at readKit")
os.exit(t.summary() and 0 or 1)
