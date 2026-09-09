local ZIL = {}

local function remoteOpen(ns, fallback)
	if not ns._readFile then return fallback end
	local remoteIO = {}
	function remoteIO.open(path, mode)
		if type(path) ~= "string" then
			error("zilscript requested a non-string file path")
		end
		if path:sub(1, 1) == "/" or (mode and mode:find("[wa+]")) then
			return fallback(path, mode)
		end
		local body, err = ns._readFile(path)
		if not body then return nil, err end
		local closed = false
		return {
			read = function(_, mode)
				if closed then return nil end
				if mode == "*a" or mode == "*all" or mode == nil then return body end
				return body
			end,
			close = function() closed = true end,
		}
	end
	return remoteIO.open
end

-- zilscript's compiler resolves imports through the host globals. Scope that
-- context to one synchronous load/resume, and restore it even after failures.
local function withContext(ns, paths, operation)
	local originalOpen, originalPath, originalZilPath = io.open, package.path, package.zilpath
	io.open = remoteOpen(ns, originalOpen)
	package.path, package.zilpath = paths.lua, paths.zil
	local result = table.pack(pcall(operation))
	io.open, package.path, package.zilpath = originalOpen, originalPath, originalZilPath
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end

function ZIL.new(game, ns)
	local sourceBase = game.id:gsub("%.", "/")
	local base = game.base or sourceBase
	local paths = {
		lua = "External/zilscript/?.lua;External/zilscript/?/init.lua;" .. package.path,
		zil = "External/zilscript/" .. sourceBase .. "/?.zil;"
			.. "External/zilscript/" .. base .. "/?.zil;"
			.. "External/zilscript/?.zil;External/zilscript/?/?.zil",
	}
	return withContext(ns, paths, function()

		local runtime = require("zilscript.runtime")
		local env = runtime.create_game_env()
		env.rawget, env.rawset, env.rawequal = rawget, rawset, rawequal
		local bootstrapPath = "External/zilscript/zilscript/bootstrap.lua"
		local bootstrap = ns._readFile and ns._readFile(bootstrapPath)
		if bootstrap then
			assert(runtime.execute(bootstrap, bootstrapPath, env, true),
				"failed to initialize zilscript")
		else
			assert(runtime.init(env), "failed to initialize zilscript")
		end
		-- The bootstrap derives its own default search path from package.path;
		-- restore the game's directory afterward so INSERT-FILE resolves relative
		-- to the selected catalog entry on both disk and streamed iOS files.
		package.zilpath = "External/zilscript/" .. sourceBase .. "/?.zil;"
			.. "External/zilscript/" .. base .. "/?.zil;"
			.. "External/zilscript/?.zil;External/zilscript/?/?.zil"

		local root = "External/zilscript/" .. sourceBase
		local start = root .. "/" .. game.startFile
		assert(runtime.load_zil_files({ start }, env, { silent = true }),
			"failed to load " .. game.title)

		return {
			start = function()
				return withContext(ns, paths, function()
					local engine = runtime.create_game(env, true)
					local opening = engine:start()
					return {
						resume = function(_, command)
							return withContext(ns, paths, function() return engine:resume(command) end)
						end,
					}, opening
				end)
			end,
		}
	end)
end

return ZIL
