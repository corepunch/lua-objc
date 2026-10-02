local Routes = require("data.routes")

-- A sheet is a request, like a page: a sheet route answers `data()` and has
-- an action per button. What is native about a sheet (the shell over the
-- window, the body drawn into it) is its presenter's, `self.presenter`
-- (controllers/SheetController.lua). What a sheet route adds to an ordinary
-- one is only this:
--
--   open(parent, ...)  present the sheet (a sheet's own `open` prepares its
--                      state and calls SheetRoute.open); `self.sheet` is set
--                      while it is up
--   draw()             ask `data()` again and draw it; the way a sheet says that
--                      work finished later
--   close()            dismiss the sheet; it is also the action of the Done button
--   every(seconds, fn) run `fn` on a timer while the sheet is up
--   sync(refs)         optional: touch native views after a draw (a selection,
--                      a switch the person flipped)
--
-- `SheetRoute.extend{view, width, height, ...}`: the body is views/<view>.etlua,
-- e.g. view = "sheets/Review".
local SheetRoute = {}

function SheetRoute.extend(route)
	return Routes.extend(SheetRoute, route)
end

function SheetRoute:open(parent)
	self:close()
	self.sheet = self.presenter:present(parent)
end

function SheetRoute:draw() self.presenter:draw() end

function SheetRoute:close()
	self.presenter:dismiss()
	self.sheet, self.refs = nil, nil
end

function SheetRoute:every(seconds, fn) self.presenter:every(seconds, fn) end

-- A sheet that moves the person between pages names the container to
-- slide in `self.slide = {id, edge}`.
function SheetRoute:rendered(refs)
	self.refs = refs
	local slide = self.slide
	self.slide = nil
	if slide then self.presenter:slide(refs[slide.id], slide.edge) end
	if self.sync then self:sync(refs) end
end

return SheetRoute
