-- A well-formed plugin: declarative fields, private helpers, a factory.
local function greeting(name) return "Hello, " .. name end
return {
	api = 1,
	title = "Hello",
	create = function(host, name)
		return {text = host.decorate(greeting(name)), folder = host.directory, art = host.resource("art.png")}
	end,
}
