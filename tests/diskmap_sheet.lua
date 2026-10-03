local Routes = require("data.routes")
local Model = require("data.model")
local Sheets = require("apps.diskmap.pages.Sheets")
local Presenter = require("apps.diskmap.controllers.SheetController")
local Contract = require("apps.diskmap.services.Contract")
local Basket = require("apps.diskmap.flows.Basket")
local Sheet = {}
function Sheet.new(id, context)
	if not pcall(require("apps.diskmap.services.Contract").check, context.service) then
		context.service = require("apps.diskmap.services.Contract").stub(context.service)
	end
	context.basketChanged = context.basketChanged or function() end
	context.basket = context.basket or Basket({app = context})
	context.basket.results, context.basket.done = {}, {}
	context.log = context.log or function() end
	if context.model then Model.bind(context.model) end
	local preferences = require("apps.diskmap.models.Session"):current()
	preferences.monitorEnabled = context.service.loadSettings() == true
	preferences.historyEnabled = context.service.loadHistorySetting() == true
	Model.db.includeMedia = context.service.loadFlag("media") == true
	local page = Routes.page(Sheets[id], {id = id}, context, "apps.diskmap")
	Presenter.attach(page, context.model or Model.db)
	return page
end
return Sheet
