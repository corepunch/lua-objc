local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("data.model")
local PageController = require("data.pagecontroller")
local Sheet = require("apps.diskmap.Sheet")

-- A sheet is a request, like a page: the model of a sheet answers `data()` and
-- has an action per button; the framework's page controller draws the body
-- template it names into the body host of one shell (views/SheetShell.etlua).
-- What a sheet's model adds to an ordinary one is only this:
--
--   open(parent, ...)  present the shell and mount the body (the model's own
--                      `open` prepares its state and calls SheetPage.open)
--   draw()             ask `data()` again and draw it; the way a model says that
--                      work finished later
--   close()            dispose the body, dismiss the sheet; it is also the
--                      action of the Done button
--   sync(refs)         optional: touch native views after a draw (a selection,
--                      a switch the person flipped)
--
-- `define{id, view, width, height}`: the body is views/<view>.etlua. The model
-- is built by the app with `Class.new({}, services)`; `services` is the
-- app's context table.
local SheetPage = {}

local VIEWS = "apps/diskmap/views/"

function SheetPage.define(spec)
	local class = Model.define({id = spec.id})
	class.view, class.shell = spec.view, {width = spec.width, height = spec.height}
	class.open, class.draw, class.close, class.rendered, class.every =
		SheetPage.open, SheetPage.draw, SheetPage.close, SheetPage.rendered, SheetPage.every
	return class
end

function SheetPage.open(self, parent)
	self:close()
	local sheet, shell = Sheet.present(function() return xml.renderFile(VIEWS .. "SheetShell.etlua", self.shell, ns) end, parent)
	self.sheet = sheet
	-- The page controller asks a graph for its model; a sheet is its own.
	local graph = {build = function() return {[self.id] = self} end}
	self.body = PageController.new({page = {id = self.id, model = self.id, view = self.view}, graph = graph, ns = ns,
		viewsDir = VIEWS})
	self.body:mount(shell.body)
end

function SheetPage.draw(self)
	if self.body then self.body:update() end
end

function SheetPage.close(self)
	if self.body then self.body:dispose() end
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.body, self.refs = nil, nil, nil
end

-- Runs `fn` every `seconds` while the sheet is up. Headless tests call
-- what `fn` does themselves instead of waiting.
function SheetPage.every(self, seconds, fn)
	if _G.__headless then return end
	local sheet = self.sheet
	ns.async(function()
		while self.sheet == sheet do
			ns.sleep(seconds)
			if self.sheet == sheet then fn() end
		end
	end)
end

-- A model that moves the person between pages of a sheet names the container
-- to slide in `self.slide = {id, edge}`; the system's push transition does it.
function SheetPage.rendered(self, refs)
	self.refs = refs
	local slide = self.slide
	self.slide = nil
	if slide then ns._pushTransition(refs[slide.id], slide.edge) end
	if self.sync then self:sync(refs) end
end

return SheetPage
