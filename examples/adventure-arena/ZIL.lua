local ZIL = {}

local function installRemoteIO(ns)
	if not ns._readFile then return end
	local remoteIO = {}
	function remoteIO.open(path)
		if type(path) ~= "string" then
			error("zilscript requested a non-string file path")
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
	io.open = remoteIO.open
end

function ZIL.new(game, ns)
	installRemoteIO(ns)
	package.path = "External/zilscript/?.lua;External/zilscript/?/init.lua;" .. package.path
	package.zilpath = "External/zilscript/" .. (game.sourceBase or game.base) .. "/?.zil;"
		.. "External/zilscript/?.zil;External/zilscript/?/?.zil"

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
	package.zilpath = "External/zilscript/" .. (game.sourceBase or game.base) .. "/?.zil;"
		.. "External/zilscript/" .. game.base .. "/?.zil;"
		.. "External/zilscript/?.zil;External/zilscript/?/?.zil"

	local root = "External/zilscript/" .. (game.sourceBase or game.base)
	local start = root .. "/" .. game.startFile
	assert(runtime.load_zil_files({ start }, env, { silent = true }),
		"failed to load " .. game.title)

	return {
		start = function()
			local engine = runtime.create_game(env, true)
			return engine, engine:start()
		end,
	}
end

return ZIL
