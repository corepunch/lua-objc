local Session = {}
Session.__index = Session

function Session.new(options)
	options = options or {}
	return setmetatable({ engineFactory = options.engineFactory, messages = {} }, Session)
end

function Session:start(game)
	if not game then return false, "Adventure not found." end
	if not self.engineFactory then return false, "No session engine configured." end
	local ok, engine, opening = pcall(function()
		return self.engineFactory(game):start()
	end)
	if not ok then return false, tostring(engine) end
	self.engine, self.currentGame = engine, game
	self.messages = { tostring(opening or "") }
	return true
end

function Session:submit(command)
	command = tostring(command or ""):match("^%s*(.-)%s*$")
	if command == "" or not self.engine then return false end
	local ok, response = pcall(function() return self.engine:resume(command) end)
	self.messages[#self.messages + 1] = "> " .. command
	self.messages[#self.messages + 1] = tostring(response or "")
	return ok, response
end

function Session:transcript()
	return table.concat(self.messages, "\n\n")
end

return Session
