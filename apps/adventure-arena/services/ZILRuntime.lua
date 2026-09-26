local ZILRuntime = {}

local function remoteOpen(readFile, fallback)
	if not readFile then return fallback end
	local remoteIO = {}
	function remoteIO.open(path, mode)
		if type(path) ~= "string" then
			error("zilscript requested a non-string file path")
		end
		if path:sub(1, 1) == "/" or (mode and mode:find("[wa+]")) then
			return fallback(path, mode)
		end
		local body, err = readFile(path)
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
local function withContext(readFile, paths, operation)
	local originalOpen, originalPath, originalZilPath = io.open, package.path, package.zilpath
	io.open = remoteOpen(readFile, originalOpen)
	package.path, package.zilpath = paths.lua, paths.zil
	local result = table.pack(pcall(operation))
	io.open, package.path, package.zilpath = originalOpen, originalPath, originalZilPath
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end

-- A private Park–Miller generator: an autosave replays its commands against
-- the same sequence, and nothing else in the app can advance it between turns
-- the way the shared math.random could.
function ZILRuntime.random(seed)
	local state = math.floor(tonumber(seed) or 1) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(m, n)
		state = state * 48271 % 2147483647
		local unit = (state - 1) / 2147483646
		if m == nil then return unit end
		if n == nil then m, n = 1, m end
		return m + math.floor(unit * (n - m + 1))
	end
end

function ZILRuntime.new(game, readFile, seed)
	local sourceBase = game.id:gsub("%.", "/")
	local base = game.base or sourceBase
	local paths = {
		lua = "apps/adventure-arena/zilscript/?.lua;apps/adventure-arena/zilscript/?/init.lua;" .. package.path,
		zil = "apps/adventure-arena/zilscript/" .. sourceBase .. "/?.zil;"
			.. "apps/adventure-arena/zilscript/" .. base .. "/?.zil;"
			.. "apps/adventure-arena/zilscript/?.zil;apps/adventure-arena/zilscript/?/?.zil",
	}
	return withContext(readFile, paths, function()

		local runtime = require("zilscript.runtime")
		local env = runtime.create_game_env()
		env.rawget, env.rawset, env.rawequal = rawget, rawset, rawequal
		env.math = setmetatable({ random = ZILRuntime.random(seed or os.time()),
			randomseed = function() end }, { __index = math })
		local bootstrapPath = "apps/adventure-arena/zilscript/zilscript/bootstrap.lua"
		local bootstrap = readFile and readFile(bootstrapPath)
		if bootstrap then
			assert(runtime.execute(bootstrap, bootstrapPath, env, true),
				"failed to initialize zilscript")
		else
			assert(runtime.init(env), "failed to initialize zilscript")
		end
		-- The bootstrap derives its own default search path from package.path;
		-- restore the game's directory afterward so INSERT-FILE resolves relative
		-- to the selected catalog entry on both disk and streamed iOS files.
		package.zilpath = "apps/adventure-arena/zilscript/" .. sourceBase .. "/?.zil;"
			.. "apps/adventure-arena/zilscript/" .. base .. "/?.zil;"
			.. "apps/adventure-arena/zilscript/?.zil;apps/adventure-arena/zilscript/?/?.zil"

		local root = "apps/adventure-arena/zilscript/" .. sourceBase
		local start = root .. "/" .. game.startFile
		assert(runtime.load_zil_files({ start }, env, { silent = true }),
			"failed to load " .. game.title)

		return {
			start = function()
				return withContext(readFile, paths, function()
					local engine = runtime.create_game(env, true)
					local opening = engine:start()
					return {
						resume = function(_, command)
							return withContext(readFile, paths, function() return engine:resume(command) end)
						end,
						progress = function()
							return {
								score = tonumber(env.SCORE) or 0,
								moves = tonumber(env.MOVES) or 0,
								maxScore = tonumber(env["SCORE-MAX"]) or 0,
							}
						end,
						roomName = function()
							return withContext(readFile, paths, function()
								local here, descId = env.HERE, env.PQDESC
								if here and descId and type(env.GETP) == "function" then
									local ok, desc = pcall(env.GETP, here, descId)
									if ok and type(desc) == "number" and env.mem then
										local readOK, name = pcall(function() return env.mem:string(desc) end)
										if readOK then return tostring(name or "") end
									elseif ok and type(desc) == "string" then
										return desc
									end
								end
								return ""
							end)
						end,
						-- Visible objects with the verbs the story accepts for
						-- them; nested entries are the contents of open things.
						items = function()
							return withContext(readFile, paths, function()
								local ok, items = pcall(function() return engine:resume("room-items") end)
								return ok and type(items) == "table" and items or {}
							end)
						end,
						exits = function()
							return withContext(readFile, paths, function()
								local ok, exits = pcall(function() return engine:resume("room-exits") end)
								local directions = {}
								if ok and type(exits) == "table" then
									for _, exit in ipairs(exits) do
										if type(exit) == "table" and exit[1] then
											table.insert(directions, tostring(exit[1]):lower())
										end
									end
								end
								return directions
							end)
						end,
					}, opening
				end)
			end,
		}
	end)
end

return ZILRuntime
