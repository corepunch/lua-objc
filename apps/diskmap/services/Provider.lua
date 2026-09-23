local Provider = {}

function Provider.select(arguments)
	for _, argument in ipairs(arguments or {}) do
		if argument == "--mock" or argument == "-mock" then
			return require("apps.diskmap.services.Mock").new()
		end
	end
	return require("apps.diskmap.services.System")
end

return Provider
