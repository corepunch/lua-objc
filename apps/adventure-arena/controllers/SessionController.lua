local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "session model is required"),
		findGame = assert(options.findGame, "adventure lookup callback is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		ns = assert(options.ns, "native platform module is required"),
	}, Controller)
end

function Controller:show(id)
	local game = self.findGame(id)
	if not game then return false end
	local ok, err = self.model:start(game)
	if not ok then
		self.push("SessionError", {
			message = err, actions = { back = self.back },
		}, game.title)
		return false
	end
	local actions = {
		submit = function() self:submitCommand(self.refs.input.text) end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		close = self.back,
	}
	self.view, self.refs = self.push("Session", {
		transcript = self.model:transcript(), actions = actions,
	}, game.title)
	self.refs.input.accessibilityLabel = "Command"
	self.ns._textFieldCallbacks(self.refs.input, nil, function(command)
		if command ~= "submit" then return false end
		actions.submit()
		return true
	end)
	return true
end

function Controller:submitCommand(command)
	local ok, err = self.model:submit(command)
	self.refs.output.text = self.model:transcript()
	self.refs.input.text = ""
	self.view:layout()
	return ok, err
end

return Controller
