-- Globals a plugin defines stay in its own environment.
counter = 0
return {
	api = 1,
	title = "Shout",
	symbol = "megaphone",
	extra = {loud = true},
	create = function(host, name)
		counter = counter + 1
		return {text = host.decorate(string.upper(name)), count = counter, hasMath = math.floor ~= nil}
	end,
}
