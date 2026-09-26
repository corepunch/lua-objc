-- Binds the shared "Themes & Settings" options to the reading preferences.
-- The in-book sheet and the Settings tab each mount the same template; every
-- mounted copy re-renders when any of them changes a preference, and the
-- change is persisted and announced so an open book re-sets its type.
local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "reading settings model is required"),
		mountTemplate = assert(options.mountTemplate, "template mount is required"),
		store = options.store,
		onChange = options.onChange or function() end,
		mounted = {},
	}, Controller)
end

-- Mounts the options into `host`; `preview` adds a sample page for places
-- where no book is open behind the controls.
function Controller:mount(host, preview)
	local template = self.mountTemplate(host, "ReadingOptions")
	local entry = { template = template, preview = preview == true }
	table.insert(self.mounted, entry)
	self:renderEntry(entry)
	return template
end

function Controller:unmount(template)
	for index, entry in ipairs(self.mounted) do
		if entry.template == template then
			table.remove(self.mounted, index)
			if not template:isDisposed() then template:dispose() end
			return true
		end
	end
	return false
end

function Controller:actions()
	local model = self.model
	local actions = {
		fontChanged = function(index) self:apply(model:setFontIndex(index)) end,
		spacingChanged = function(index) self:apply(model:setSpacingIndex(index)) end,
		sizeChanged = function(value)
			local before = model.fontSize
			model:setFontSize(value)
			-- A slider reports every point it passes; re-set the book only on a
			-- new size, and leave the panel alone so the slider stays under the
			-- reader's finger.
			if model.fontSize ~= before then self:apply(true, true) end
		end,
		decreaseSize = function() self:apply(model:adjustFontSize(-1)) end,
		increaseSize = function() self:apply(model:adjustFontSize(1)) end,
		justifyChanged = function(on) self:apply(model:setJustified(on)) end,
	}
	for index = 0, #model.themes() - 1 do
		actions["theme_" .. index] = function() self:apply(model:setThemeIndex(index)) end
	end
	return actions
end

function Controller:renderEntry(entry)
	if entry.template:isDisposed() then return end
	local data = self.model:presentation()
	data.preview = entry.preview
	data.actions = self:actions()
	entry.template:update(data)
end

function Controller:apply(changed, keepPanel)
	if not changed then return false end
	for index = #self.mounted, 1, -1 do
		local entry = self.mounted[index]
		if entry.template:isDisposed() then table.remove(self.mounted, index)
		elseif not keepPanel then self:renderEntry(entry) end
	end
	if self.store and self.store.save then self.store.save(self.model:snapshot()) end
	self.onChange(self.model:presentation())
	return true
end

return Controller
