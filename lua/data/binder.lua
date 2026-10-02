-- The generic controller's binding half: WPF's DataContext machinery for a
-- page. `xml.render` records each `$path` attribute of a page template as an
-- entry (view, native property, kind, record path); the binder projects the
-- page's model through its schema and sets those properties, so a page needs
-- no controller that copies model values into views.
--
-- Propagation is explicit, as WPF's PropertyChanged with an empty property
-- name: models are plain Lua data and are not observed, so whoever changes a
-- model calls `update()` and every entry is set again. Animation stays the
-- caller's choice: wrap `update()` in `ns.withAnimation`.
--
-- `propagates`: set when a model graph rebinds the page after a change (it
-- calls `changed`); the binder then does not update itself.
--
-- Two-way entries (Toggle `isOn`, TextField `text`, Picker `selection`)
-- write back through the model's `set<Field>` setter. A setter returning
-- `false` refuses the edit; either way `update()` runs next, so a refused
-- edit shows the model's value again.
local Schema = require("data.schema")

local Binder = {}
Binder.__index = Binder

function Binder.new(options)
	assert(options and options.schema, "Binder needs a schema")
	return setmetatable({
		schema = options.schema,
		model = options.model,
		now = options.now,
		-- Called after a command ran or a write was accepted, before the
		-- views are set again: the model graph marks dependents stale here.
		changed = options.changed or function() end,
		entries = {},
		applying = false,
	}, Binder)
end

function Binder:setModel(model)
	self.model = model
end

local function systemColor(name)
	local ok, bridge = pcall(require, "AppKitNative")
	if not ok then ok, bridge = pcall(require, "UIKitNative") end
	return ok and bridge._systemColor and bridge._systemColor(name) or nil
end

-- One entry: { view, key, kind, path, negate, apply, fallback }.
function Binder:add(entry)
	if entry.key and entry.fallback == nil then
		local ok, value = pcall(function() return entry.view[entry.key] end)
		if ok then entry.fallback = value end
	end
	table.insert(self.entries, entry)
	return entry
end

local function coerce(entry, value)
	local kind = entry.kind
	if kind == "bool" then
		return Schema.truthy(value) ~= (entry.negate == true)
	elseif kind == "rows" then
		return value or {}
	elseif value == nil then
		return entry.fallback
	elseif kind == "number" then
		local number = tonumber(value)
		if number == nil or number ~= number or number == math.huge or number == -math.huge then return entry.fallback end
		return number
	elseif kind == "color" then
		return systemColor(tostring(value)) or entry.fallback
	end
	return tostring(value)
end

-- The model a context path (`{"lead"}`) designates, following Record
-- fields' sources.
function Binder:modelAt(prefix)
	local model, schema = self.model, self.schema
	for _, id in ipairs(prefix or {}) do
		local field = schema.byId[id]
		local nested = model[field.source]
		if type(nested) == "function" then nested = nested(model) end
		model, schema = nested, schema:related(field)
	end
	return model, schema
end

-- Projects the model and sets every bound property.
function Binder:update()
	if not self.model then return end
	local record = self.schema:project(self.model, { now = self.now })
	self.record = record
	self.applying = true
	local ok, err = pcall(function()
		for _, entry in ipairs(self.entries) do
			local value = coerce(entry, Schema.lookup(record, entry.path))
			if entry.apply then
				if value ~= nil then entry.apply(entry.view, value) end
			elseif entry.view[entry.key] ~= value then
				entry.view[entry.key] = value
			end
		end
	end)
	self.applying = false
	if not ok then error(err, 0) end
end

-- The model behind a list row an event handed back (`row.__row` indexes the
-- raw rows of the last projection of the list at `rowsPath`).
function Binder:rowModel(rowsPath, row)
	local raw = {}
	for index = 1, #rowsPath - 1 do raw[index] = rowsPath[index] end
	raw[#rowsPath] = rowsPath[#rowsPath] .. "#raw"
	local rows = self.record and Schema.lookup(self.record, raw)
	return rows and rows[row.__row] or nil
end

-- Runs the command `name` of the model at `prefix`; given a list event's
-- arguments it receives the row's model. A command declared `query="true"` (a menu to
-- build, a value to read) returns its results and changes nothing; any other
-- is a change and the views are set again.
function Binder:invoke(prefix, name, rowsPath, ...)
	local model, schema = self:modelAt(prefix)
	local args = table.pack(...)
	-- A list event reports (index, column, row): the command takes the row's
	-- model alone. Other events pass their arguments through.
	for index = 1, args.n do
		local value = args[index]
		if rowsPath and type(value) == "table" and type(value.__row) == "number" then
			args = table.pack(self:rowModel(rowsPath, value) or value)
			break
		end
	end
	local results = table.pack(model[name](model, table.unpack(args, 1, args.n)))
	if schema.byId[name].attrs.query ~= "true" then
		self.changed(model)
		if not self.propagates then self:update() end
	end
	return table.unpack(results, 1, results.n)
end

-- A window's own bindings (title, subtitle), once its owner has created it.
function Binder:addWindow(config, window)
	for _, entry in ipairs(config.bindings or {}) do
		entry.view = window
		self:add(entry)
	end
end

-- Writes a control's new value to the field's setter. Returns whether the
-- model accepted it.
function Binder:write(prefix, id, value)
	if self.applying then return true end
	local model = self:modelAt(prefix)
	local accepted = model[Schema.setterName(id)](model, value) ~= false
	if accepted then self.changed(model) end
	-- A refused edit still rebinds: the control shows the model's value again.
	if not accepted or not self.propagates then self:update() end
	return accepted
end

return Binder
