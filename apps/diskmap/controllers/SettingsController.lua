local Controller = {}; Controller.__index = Controller
function Controller.new(service)
	return setmetatable({service = service, enabled = not service.loadSettings or service.loadSettings()}, Controller)
end
function Controller:toggle()
	local enabled = not self.enabled
	if self.service.saveSettings and not self.service.saveSettings(enabled) then return false end
	self.enabled = enabled; return true
end
function Controller:presentation(toggle, openSettings)
	return {monitoring = self.enabled, actions = {monitor = toggle, storage = openSettings}}
end
return Controller
