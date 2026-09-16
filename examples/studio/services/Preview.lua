-- Each evaluation gets its own module cache and globals. The native runtime is shared.
local Preview = {}
Preview.__index = Preview

function Preview.new(ns, readFramework)
	return setmetatable({ ns = ns, readFramework = readFramework }, Preview)
end

function Preview:render(files)
	local env, loaded = {}, {}
	for _, key in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type", "xpcall", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "print", "unpack" }) do env[key] = _G[key] end
	for _, key in ipairs({ "math", "string", "table", "utf8", "coroutine" }) do
		env[key] = {}; for k, v in pairs(_G[key]) do env[key][k] = v end
	end
	env._G = env
	local ns = {}
	for key, value in pairs(self.ns) do
		if key:sub(1, 1) ~= "_" then ns[key] = value end
	end
	ns.Window = function(config)
		local content = config.content or config[1]
		if type(content) == "table" then content = self.ns.VStack(content) end
		return self.ns.HostingController(content)
	end
	local function read(path)
		local source = assert(files[path], "Project file not found: " .. tostring(path))
		return source
	end
	local reader = { _readFile = read }
	env.io = { stderr = { write = function() end } }
	env.os = { time = os.time, date = os.date, difftime = os.difftime, clock = os.clock }
	env.load = function(source, name, mode, scope) return load(source, name, "t", scope or env) end
	env.loadstring = function(source, name) return load(source, name, "t", env) end
	env.setfenv = function(fn, scope)
		for index = 1, math.huge do
			local name = debug.getupvalue(fn, index)
			if not name then break end
			if name == "_ENV" then
				debug.upvaluejoin(fn, index, function() return scope end, 1)
				break
			end
		end
		return fn
	end
	local function requireModule(name)
		if name == "ns" or name == "UIKit" or name == "AppKit" then return ns end
		if name == "UIKitNative" or name == "AppKitNative" then return reader end
		if loaded[name] ~= nil then return loaded[name] end
		local source, path
		if name == "ui.xml" then
			path = "lua/ui/xml.lua"; source = self.readFramework(path)
		elseif name == "etlua" then
			path = "lua/vendor/etlua/etlua.lua"; source = self.readFramework(path)
		else
			path = name:gsub("%.", "/") .. ".lua"
			source = read(path)
		end
		loaded[name] = true
		local chunk = assert(load(source, "@" .. path, "t", env))
		local result = chunk()
		loaded[name] = result == nil and true or result
		return loaded[name]
	end
	env.require = requireModule
	local oldHook, mask, count = debug.gethook()
	local ticks = 0
	debug.sethook(function()
		ticks = ticks + 1
		if ticks > 500 then error("Preview exceeded its execution budget") end
	end, "", 10000)
	local ok, result = xpcall(function()
		local controller = requireModule("examples.playground.init").new()
		return controller:createWindow()
	end, debug.traceback)
	debug.sethook(oldHook, mask, count)
	if not ok then return nil, result end
	return result
end
return Preview
