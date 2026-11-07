-- Deterministic UIKit harness; run make studio-smoke. No key or network.
local Root = require("apps.studio.Controller")
local Harness = setmetatable({}, {__index = Root})
Harness.__index = Harness
local COUNTER = [[local Model = require("data.model")
local Counters, Counter = Model:extend("starterCounters", {primaryKey = "id"})
function Counter:increment() return self:update({value=self.value+2}) end
return Counters]]

function Harness.new()
	local ns, state = require("ns"), {responses = 0}
	local app = Root.new({device = {
		json = {encode = ns._jsonEncode, decode = ns.json_parse},
		github = {
			credentials = {read = function() return nil end, save = function() return true end, clear = function() return true end},
			request = function(_, _, _, _, callback) callback({login="octocat",id=1,name="Example Author"}); return function() end end,
		},
		credentials = {read = function() return "smoke-test-only" end},
		transport = function(_, _, callback)
			state.responses = state.responses + 1
			local response = {content = "Updated the counter to add two. Try it in the preview."}
			if state.responses == 1 then
				response = {tool_calls = {{id = "edit", ["function"] = {name = "applyFiles",
					arguments = ns._jsonEncode({files = {{path = "demo/playground/Model.lua", content = COUNTER}}})}}}}
			end
			local active = true
			ns._timerAfter(0, function() if active then callback({choices = {{message = response}}}) end end)
			return function() active = false end
		end,
	}})
	app.smokeState = state
	app.nativeCredentials = require("apps.studio.services.Device").new(ns).credentials
	if (os.getenv("STUDIO_SMOKE_SCENARIO") or ""):match("^github%-live") then
		app.device.github = require("apps.studio.services.Device").new(ns).github
	end
	return setmetatable(app, Harness)
end

function Harness:createWindow()
	local window = Root.createWindow(self)
	local ns = self.ns
	local scenario = os.getenv("STUDIO_SMOKE_SCENARIO") or "agent"
	if not scenario:match("^lifecycle%-") then
		assert(self:openProject("StarterApp"))
		assert(self.activeProject.id == "StarterApp", "the active project did not switch")
	end
	local function finish(ok, err)
		assert(ns._documentWrite("smoke-result.txt", ok and ("PASS " .. scenario) or ("FAIL " .. tostring(err))))
		ns._captureInternal()
	end
	if scenario:match("^github%-live") then
		ns._timerAfter(0.5, function()
			local ok, err = xpcall(function() require("test.studio-smoke.GitHubWorkflow").run(self, scenario, finish) end, debug.traceback)
			if not ok then finish(false, err) end
		end)
		return window
	end
	if scenario == "agent" then
		local changed = self.chat.agent.changed
		self.chat.agent.changed = function()
			changed()
			if self.chat.agent.busy then return end
			finish(xpcall(function()
				assert(self.smokeState.responses == 2, self.model:transcript())
				assert(self.model.files["demo/playground/Model.lua"]:find("value+2", 1, true), "generated edit was not saved")
				assert(self.previewContent, "generated app did not preview")
			end, debug.traceback))
		end
		self.chat.draft = "Change the starter counter to add two."
		assert(self:sendMessage())
		return window
	end
	if scenario == "code" then
		self.actions.showCode()
		ns._textEditorTestInput(self.refs.sourceCode, self.model.files["demo/playground/Controller.lua"] .. "\n-- Edited on iPad\n")
		assert(self.model.drafts["demo/playground/Controller.lua"], "native edit did not reach the model")
		assert(self.refs.sourceCode.editable)
		assert(self.refs.codeFiles.rowCount == #self.model:listFiles(), "file tree did not switch")
		assert(self.actions.saveSource())
	elseif scenario == "long" then
		self.activeProject.title = string.rep("A long project name ", 4)
		self.model:message("user", string.rep("Create a native app with MVC, an editable preview, and clean layout. ", 8))
		self.model:message("error", "A sample connection error. The source and last working preview remain available.")
		self:render()
	elseif scenario == "busy" then
		self.chat.agent.busy = true
		self:render()
	end
	ns._timerAfter(0.5, function()
		finish(xpcall(function()
			if scenario == "orientation" then
				local controller = window.rootViewController
				assert(controller.supportedInterfaceOrientations == 24, "Studio permits an orientation outside landscape")
				assert(controller.prefersInterfaceOrientationLocked, "Studio did not request the native orientation lock")
				local orientation = window.windowScene.effectiveGeometry.interfaceOrientation
				assert(orientation == 3 or orientation == 4, "The actual iPad scene is not landscape")
				assert(ns._documentWrite("orientation.json", ns._jsonEncode({landscape=true, orientation=orientation, supportedMask=24})))
			elseif scenario == "lifecycle-create" then
				if ns._documentExists("WorkflowProof/project.lua") then assert(self.catalog:delete("WorkflowProof")) end
				self:showNewProject()
				ns._textFieldTestInput(self.sheets.template.refs.projectName, "Workflow Proof")
				assert(self.actions.createProject())
				assert(self.activeProject.id == "WorkflowProof" and self.previewContent)
				assert(#self.versions:log() == 1, "creation must include an initial Git commit")
			elseif scenario:match("^lifecycle%-") then
				if scenario ~= "lifecycle-recreate" and scenario ~= "lifecycle-empty" then assert(self:openProject("WorkflowProof")) end
				if scenario == "lifecycle-settings" then
					self.device.credentials = self.nativeCredentials
					self:showSettings()
					ns._textFieldTestInput(self.sheets.template.refs.apiKey, "workflow-test-only")
					self.actions.saveCredential()
					assert(self.device.credentials.read() == "workflow-test-only", "Keychain did not save the key")
					ns._textFieldTestInput(self.sheets.template.refs.modelId, "openrouter/auto")
					self.actions.saveModel()
					assert(self.model.modelId == "openrouter/auto")
				elseif scenario == "lifecycle-edit" then
					self.actions.selectProjectIcon_desk()
					self.actions.showCode()
					self:selectFile("views/pages/Main.etlua")
					local source = self.model:source("demo/playground/views/pages/Main.etlua"):gsub("My App", "Workflow Saved")
					ns._textEditorTestInput(self.refs.sourceCode, source)
					assert(self.actions.saveSource())
					assert(self.actions.reloadPreview())
					assert(self.actions.commitProject())
					assert(ns._documentRead("WorkflowProof/views/pages/Main.etlua"):find("Workflow Saved",1,true))
				elseif scenario == "lifecycle-invalid" then
					self.actions.showCode();self:selectFile("Model.lua")
					local working = self.previewContent
					ns._textEditorTestInput(self.refs.sourceCode, "local broken = !!!")
					assert(not self.actions.reloadPreview(), "invalid Lua must fail Save and Run")
					assert(self.previewContent == working, "invalid Lua replaced the last working preview")
					assert(not ns._documentRead("WorkflowProof/Model.lua"):find("!!!",1,true), "invalid draft overwrote saved source")
				elseif scenario == "lifecycle-reopen" then
					assert(self.model.modelId == "openrouter/auto", "model setting did not survive relaunch")
					assert(self.nativeCredentials.read() == "workflow-test-only", "Keychain did not survive relaunch")
					assert(self.activeProject.projectIcon == "desk", "icon selection did not survive relaunch")
					assert(self.model.files["demo/playground/views/pages/Main.etlua"]:find("Workflow Saved",1,true), "saved source did not survive relaunch")
					assert(#self.versions:log() == 2, "Git history did not survive relaunch")
					self.actions.showCode();self:selectFile("views/pages/Main.etlua")
					assert(self.nativeCredentials.clear())
				elseif scenario == "lifecycle-delete-confirm" then
					self.actions.showDeleteProject()
				elseif scenario == "lifecycle-delete" then
					self.actions.showDeleteProject();ns.dismiss();assert(self:deleteProject(self.activeProject.id))
					assert(not ns._documentExists("WorkflowProof"), "project folder survived deletion")
					for _, project in ipairs(self.catalog:list()) do assert(project.id ~= "WorkflowProof") end
				elseif scenario == "lifecycle-empty" then
					-- This bundle is a disposable test app; exercise removal of every
					-- project without touching the product app's Documents directory.
					for _, project in ipairs(self.catalog:list()) do
						if project.id ~= self.activeProject.id then assert(self.catalog:delete(project.id)) end
					end
					self.actions.showDeleteProject();ns.dismiss();assert(self:deleteProject(self.activeProject.id))
					assert(#self.catalog:list() == 0 and self:workspaceData().empty)
				elseif scenario == "lifecycle-recreate" then
					assert(not self.activeProject, "deleted bundled projects returned on relaunch")
					self:showNewProject()
					ns._textFieldTestInput(self.sheets.template.refs.projectName, "StarterApp")
					assert(self.actions.createProject())
					assert(self.activeProject.id == "StarterApp" and self.previewContent)
				end
			elseif scenario == "github-prepare" then require("test.studio-smoke.GitHubWorkflow").prepare(self)
			elseif scenario:match("^github") then
				self.actions.showGitHub()
				if scenario=="github-busy" then self.github.busy=true;self.github:refresh("Publishing commits…") end
				if scenario=="github-error" then self.github:refresh("GitHub HTTP 403: This token cannot push to that repository. Check the Contents read/write permission.") end
			elseif scenario == "settings" or scenario == "popup-settings" then
				self:showSettings()
				assert(window.rootViewController.presentedViewController.navigationBar, "Settings is missing its native navigation bar")
			elseif scenario == "popup-delete" then
				self.actions.showDeleteProject()
				assert(window.rootViewController.presentedViewController.preferredStyle == 1, "Deletion is not a native alert")
			elseif scenario == "project" then self:showNewProject()
			elseif scenario == "templates" then self:showCatalog("Templates")
			elseif scenario == "template-create" then
				self:showCatalog("Templates")
				local shell = self.sheets.template
				self.actions.newHabit()
				assert(self.sheets.template == shell, "template choice started a second native presentation")
				ns._textFieldTestInput(self.sheets.template.refs.projectName, "Template Proof")
				assert(self.actions.createProject())
				assert(self.activeProject.title == "Template Proof" and self.previewContent)
				assert(self.model.files["demo/playground/views/Today.etlua"], "Habit Tracker template was not selected")
			elseif scenario == "export" then self.actions.showExport()
			elseif scenario == "share" then assert(self:shareProject())
			elseif scenario == "attach" then self.device.importText = ns.importTextFiles; self.actions.attachContext()
			elseif scenario == "appearance" then
				self.actions.toggleAppearance(); self.actions.toggleZoom()
				assert(self.refs.preview.appearance == "dark" and self.refs.preview.zoom == 0.75)
			elseif scenario == "create" then
				self:showNewProject()
				ns._textFieldTestInput(self.sheets.template.refs.projectName, "Smoke App")
				assert(self:createProject())
				assert(self.activeProject.title == "Smoke App" and self.previewContent)
				assert(self.refs.codeFiles.rowCount == #self.model:listFiles())
			end
		end, debug.traceback))
	end)
	return window
end
return Harness
