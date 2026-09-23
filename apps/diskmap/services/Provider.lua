local Provider = {}

local function argumentValue(arguments, flag)
	for index, argument in ipairs(arguments or {}) do
		if argument == flag then return arguments[index + 1] end
		local prefix = flag .. "="
		if type(argument) == "string" and argument:sub(1, #prefix) == prefix then return argument:sub(#prefix + 1) end
	end
end

function Provider.select(arguments)
	local fixturePath = argumentValue(arguments, "--mock-file") or argumentValue(arguments, "-mock-file")
	if fixturePath then return require("apps.diskmap.services.Mock").new({fixturePath = fixturePath}) end
	for _, argument in ipairs(arguments or {}) do
		if argument == "--mock" or argument == "-mock" then
			return require("apps.diskmap.services.Mock").new()
		end
	end
	return require("apps.diskmap.services.System")
end

function Provider.exportPath(arguments)
	return argumentValue(arguments, "--export-mock")
end

return Provider
