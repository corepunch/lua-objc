local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("data.model")
local Routes = require("data.routes")
local PageController = require("data.pagecontroller")
local Sheet = require("apps.diskmap.Sheet")

-- A sheet is a request, like a page: a sheet route answers `data()` and has
-- an action per button; the framework's page controller draws the body
-- template it names into the body host of one shell (views/sheets/SheetShell.etlua).
-- What a sheet route adds to an ordinary one is only this:
--
--   open(parent, ...)  present the shell and mount the body (a sheet's own
--                      `open` prepares its state and calls SheetRoute.open)
--   draw()             ask `data()` again and draw it; the way a sheet says that
--                      work finished later
--   close()            dispose the body, dismiss the sheet; it is also the
--                      action of the Done button
--   sync(refs)         optional: touch native views after a draw (a selection,
--                      a switch the person flipped)
--
-- `SheetRoute.extend{view, width, height, ...}`: the body is views/<view>.etlua,
-- e.g. view = "sheets/Review". The root controller builds each sheet once
-- with `SheetRoute.page(route, id, app)`.
local SheetRoute = {}

local VIEWS = "apps/diskmap/views/"

function SheetRoute.extend(route)
	return Routes.extend(SheetRoute, route)
end

-- The sheet `id` built from `route`, with the app's services as `self.app`;
-- `app.model`, the app's store, is the one the sheet reads.
function SheetRoute.page(route, id, app)
	if app.model then Model.bind(app.model) end
	return Routes.page(route, {id = id}, app, "apps.diskmap")
end

function SheetRoute:open(parent)
	self:close()
	local sheet, shell = Sheet.present(function()
		return xml.renderFile(VIEWS .. "sheets/SheetShell.etlua", {width = self.width, height = self.height}, ns)
	end, parent)
	self.sheet = sheet
	self.body = PageController.new({page = {id = self.id}, request = self, ns = ns, viewsDir = VIEWS, store = Model.db})
	self.body:mount(shell.body)
end

function SheetRoute:draw()
	if self.body then self.body:update() end
end

function SheetRoute:close()
	if self.body then self.body:dispose() end
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.body, self.refs = nil, nil, nil
end

-- Runs `fn` every `seconds` while the sheet is up. Headless tests call
-- what `fn` does themselves instead of waiting.
function SheetRoute:every(seconds, fn)
	if _G.__headless then return end
	local sheet, store = self.sheet, Model.db
	ns.async(function()
		while self.sheet == sheet do
			ns.sleep(seconds)
			if self.sheet == sheet then Model.bind(store); fn() end
		end
	end)
end

-- A sheet that moves the person between pages names the container to
-- slide in `self.slide = {id, edge}`; the system's push transition does it.
function SheetRoute:rendered(refs)
	self.refs = refs
	local slide = self.slide
	self.slide = nil
	if slide then ns._pushTransition(refs[slide.id], slide.edge) end
	if self.sync then self:sync(refs) end
end

return SheetRoute
