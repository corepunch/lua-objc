local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("test.paragraph-actions.Model")
local Controller = {}
Controller.__index = Controller
function Controller.new() return setmetatable({}, Controller) end
function Controller:createWindow()
	local rows, actions = Model.rows(), {}
	for rowIndex, row in ipairs(rows) do
		for itemIndex, verb in ipairs(row.verbs) do
			local command = row.word == "north" and "north" or verb:lower() .. " " .. row.word
			actions["choose_" .. rowIndex .. "_" .. itemIndex] = function() self.refs.status.text = command end
		end
	end
	local config, refs = xml.renderFile("test/paragraph-actions/views/Window.etlua", { rows = rows, actions = actions }, ns)
	self.refs = refs
	local window = ns.Window(config)
	local menuCase = tonumber(os.getenv("LUA_OBJC_PARAGRAPH_MENU_CASE"))
	if ns.platform == "UIKit" and menuCase then
		ns.async(function()
			ns.sleep(1)
			require("UIKitNative")._testParagraphEditMenu(refs["word_" .. menuCase], 1)
		end)
	end
	return window
end
return Controller
