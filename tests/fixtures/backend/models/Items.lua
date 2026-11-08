-- A remote model for tests/manifest_backend.test.lua.
local Model = require("data.model")
return Model:extend("fixture_items", {
	remote = "private",
	fields = {title = "string(120)", done = "boolean?"},
	indexes = {{"createdAt desc"}},
})
