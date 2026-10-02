local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("data.model")
local Routes = require("data.routes")
local PageController = require("data.pagecontroller")

-- Presents one sheet of the window. The sheet itself is a route
-- (pages/SheetRoute.lua and pages/sheets/): this controller owns what is
-- native about it. It presents one shell (views/sheets/SheetShell.etlua) over
-- the window, has the framework's page controller draw the route's view into
-- the shell's body, runs the timer of a sheet that polls, and slides a
-- sheet's pages with the system's push transition.
local SheetController = {}; SheetController.__index = SheetController

local VIEWS = "apps/diskmap/views/"
-- Sheets keep an 80 point margin inside the window on narrow windows.
local INSET = 80

-- Presents a sheet built by `build`, which returns (sheet, refs), like
-- ns.presentSheet; the sheet owns everything the builder creates.
function SheetController.presentSheet(build, parent)
	return ns.presentSheet(function()
		local sheet, refs = build()
		local width = parent.size.width - INSET
		if width > 0 and sheet.size.width > width then sheet:resize(width, sheet.size.height) end
		return sheet, refs
	end, {parent = parent})
end

-- The sheet `id` built from `route`, with the app's services as `self.app`
-- and its presenter as `self.presenter`. `app.model`, the window's store, is
-- the one the sheet reads.
function SheetController.page(route, id, app)
	if app.model then Model.bind(app.model) end
	local page = Routes.page(route, {id = id}, app, "apps.diskmap")
	page.presenter = setmetatable({page = page, store = app.model}, SheetController)
	return page
end

-- Presents the shell over `parent` and draws the route into it; returns the sheet.
function SheetController:present(parent)
	local page = self.page
	local sheet, shell = SheetController.presentSheet(function()
		return xml.renderFile(VIEWS .. "sheets/SheetShell.etlua", {width = page.width, height = page.height}, ns)
	end, parent)
	self.sheet = sheet
	self.body = PageController.new({page = {id = page.id}, request = page, ns = ns, viewsDir = VIEWS, store = self.store or Model.db})
	self.body:mount(shell.body)
	return sheet
end

function SheetController:draw()
	if self.body then self.body:update() end
end

function SheetController:dismiss()
	if self.body then self.body:dispose() end
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.body = nil, nil
end

-- Runs `fn` every `seconds` while the sheet is up, with the sheet's store
-- bound. Headless tests call what `fn` does themselves instead of waiting.
function SheetController:every(seconds, fn)
	if _G.__headless then return end
	local sheet, tick = self.sheet, Model.bound(self.store or Model.db, fn)
	ns.async(function()
		while self.sheet == sheet do
			ns.sleep(seconds)
			if self.sheet == sheet then tick() end
		end
	end)
end

function SheetController:slide(view, edge) ns._pushTransition(view, edge) end

return SheetController
