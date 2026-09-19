_G.__headless = true
local t = require("TestKit")
local native = require("AppKit")
local Controller = require("apps.studio.Controller")
local key, credentialError, sheet, focused, pending, requestCount = "", nil, nil, nil, nil, 0
local ns = {
	_readFile = function(path)
		local file = assert(io.open(path)); local source = file:read("*a"); file:close(); return source
	end,
	_documentRead = function() return nil end,
	_documentWrite = function() return true end,
	_jsonEncode = function() return "{}" end,
	json_parse = native.json_parse,
	_credential = function(_, value)
		if credentialError then error(credentialError) end
		if value ~= nil then key = value end
		return key
	end,
	_httpRequest = function(_, _, _, completion)
		requestCount = requestCount + 1; pending = completion; return {}
	end,
	_cancelRequest = function() pending = nil end,
	_focus = function(view) focused = view end,
	presentSheet = function(view) sheet = view end,
	dismiss = function() sheet = nil end,
}
local function record(kind)
	return function(props)
		props = type(props) == "table" and props or { text = props }
		props.kind = kind
		if kind == "TextField" then props.text = props.value or "" end
		return setmetatable(props, { __newindex = function(object, name, value)
			assert(not ({ autocorrectionType = true, autocapitalizationType = true,
				smartQuotesType = true, smartDashesType = true, spellCheckingType = true })[name],
				"UIKit forwarded keyboard traits cannot be assigned through KVC")
			rawset(object, name, value)
		end })
	end
end
for _, name in ipairs({ "Window", "Preview", "HostingController", "VStack", "HStack", "Spacer", "Button", "Label", "Text", "TextEditor", "TextField", "SystemImage" }) do ns[name] = record(name) end
local savedNS = package.loaded.ns
package.loaded.ns = ns
local controller = Controller.new()
controller:createWindow()
local refs = controller.refs
local function find(view, title)
	if view.title == title then return view end
	for _, child in ipairs(view) do
		local found = find(child, title); if found then return found end
	end
end
refs.files.action()
t.expect(sheet ~= nil, "Files button presents the editor")
t.expect(find(sheet, "Open") ~= nil, "file sheet exposes Open")
local initialPreview = refs.preview.content
find(sheet, "Save and preview").action()
t.assertEqual(controller.model.revision, 1, "Save and preview mutates the project")
t.expect(refs.preview.content ~= initialPreview, "saving rebuilds preview")
ns.dismiss()
refs.settings.action()
t.expect(find(sheet, "Save settings") ~= nil, "Settings button presents settings")
find(sheet, "Use free router").action()
find(sheet, "Save settings").action()
t.expect(sheet == nil, "saving settings dismisses sheet")
local loads = controller.previewLoads
refs.reload.action()
t.assertEqual(controller.previewLoads, loads + 1, "Reload button rebuilds preview")
t.expect(refs.status.text:find("load " .. controller.previewLoads, 1, true), "Reload gives visible feedback")
refs.voice.action()
t.assertEqual(focused, refs.composer, "Dictate focuses the composer for keyboard dictation")
refs.send.action()
t.expect(sheet ~= nil, "Send without credentials presents Settings")
credentialError = "Keychain error -34018"
refs.settings.action()
t.expect(sheet ~= nil, "Keychain failure does not prevent settings from opening")
refs.send.action()
t.expect(refs.status.text:find("Cannot read API key", 1, true), "Send reports Keychain errors")
t.assertEqual(requestCount, 0, "missing credentials never start a network request")
credentialError, key, refs.composer.text = nil, "test-only-key", "Change the title"
refs.send.action()
t.assertEqual(requestCount, 1, "Send reaches mocked transport when configured")
t.assertEqual(refs.composer.text, "", "successful Send clears composer")
t.assertEqual(refs.send.enabled, false, "Send disabled while request is pending")
refs.stop.action()
t.assertEqual(refs.send.enabled, true, "Stop restores Send")
t.expect(pending == nil, "Stop cancels the pending request")
package.loaded.ns = savedNS
os.exit(t.summary() and 0 or 1)
