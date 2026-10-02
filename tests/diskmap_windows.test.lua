-- Two windows (an opened scan beside this Mac) each read their own store:
-- models read the bound store, and a window binds its own whenever its code
-- runs, from a page action or from a service calling back.
_G.__headless = true
local t = require("TestKit")
local Model = require("data.model")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Locations = require("apps.diskmap.models.Locations")

local first = Controller.new(Mock.new())
first:createWindow()
local second = Controller.new(Mock.new())
second:createWindow()
t.expect(first.model ~= second.model, "each window has a store")
t.expect(Model.db == second.model, "the newest window's store is bound")

-- A service calling back into the first window binds its store.
local seen
first.service.measure({first.model.home}, function() seen = Model.db end)
t.expect(seen == first.model, "a callback of the first window's service reads the first store")

-- A page action binds the store of the window it belongs to.
Model.bind(second.model)
first:show("map")
first.pages.map.actions.pickStyle(1)
t.expect(Model.db == first.model, "an action of the first window reads the first store")
t.expect(first:request("map").style == "rectangles" and second:request("map").style == "rings", "and changes only its own page")

-- A location one window discovers is not the other's.
Model.bind(first.model)
assert(Locations:add("developer", {id = "only-first", name = "First", subtitle = "Only in the first window", path = "/tmp/only-first"}))
Model.bind(second.model)
t.expect(Locations:find("only-first") == nil, "the second store does not have the first window's location")
Model.bind(first.model)
t.expect(Locations:find("only-first") ~= nil, "the first store does")

os.exit(t.summary() and 0 or 1)
