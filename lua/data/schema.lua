-- Schemas: the fields a view may bind to, declared as XML (a `schemas/`
-- folder in each app). The tag is the type, a template string composes.
--
--   <Schema id="StorageRow" extends="Base">
--   	<String  id="name" />
--   	<Bytes   id="size" source="bytes" missing="Not measured">
--   		<State id="calculating" text="Calculating…" />
--   		<State id="denied" text="No access" icon="lock.fill" color="systemOrange" />
--   	</Bytes>
--   	<Percent id="share" source="relative" digits="0" below="&lt;1%" />
--   	<Date    id="lastUsed" style="relative" format="Used $value" />
--   	<String  id="accessibility" format="$name: $size $share" />
--   	<Bool    id="history" writable="true" />
--   	<Command id="mark" enabled="markable" />
--   	<List    id="rows" of="StorageRow" />
--   	<Record  id="lead" of="StorageRow" />
--   </Schema>
--
-- Type tags convert (`<Bytes>`, `<Number>`, `<Percent>`, `<Date>` run on the
-- system formatters); `format` only arranges already converted fields.
-- A model is validated against its schema, and `project` turns a model into
-- the record views bind to. The record is flat for the native cell binding
-- (src/appkit/table_cell_template.m): a field `size` yields
--
--   size            the display string ("1.2 GB", or the active state's text)
--   size.value      the raw number, for numeric attributes (Gauge value)
--   size.color      the active state's color, size.icon its symbol
--   size.<state>    true while that state is active (size.calculating)
--   size.state      the id of the active state
--   mark.enabled    for a Command: whether its enabling field is truthy
--
-- A List field projects to an array of records, a Record field to a nested
-- record; both use the schema named by `of`.
local Schema = {}
Schema.__index = Schema

local TYPES = {
	String = true, Number = true, Bool = true, Bytes = true, Percent = true,
	Date = true, Symbol = true, Color = true, Command = true, List = true, Record = true,
}
-- Raw values of these are numbers: a numeric attribute binds `field.value`.
local NUMERIC = { Number = true, Bytes = true, Percent = true, Date = true }
local SUFFIXES = { value = true, color = true, icon = true, state = true, enabled = true }

local function fail(schema, message)
	error("schema " .. (schema and schema.id or "?") .. ": " .. message, 0)
end

local function native()
	local ok, bridge = pcall(require, "AppKitNative")
	if not ok then ok, bridge = pcall(require, "UIKitNative") end
	return ok and bridge or {}
end

-- ── Loading ────────────────────────────────────────────────────────────

-- `loader(id)` returns the parsed schema `id` (extends= and of= name other
-- schemas); `Schema.directory` builds one that reads `<dir>/<id>.xml`.
function Schema.parse(nodes, loader)
	local root
	for _, node in ipairs(nodes) do
		if node.kind == "element" then
			if node.tag ~= "Schema" then error("schema: the document root must be <Schema>, not <" .. node.tag .. ">", 0) end
			root = node
		end
	end
	if not root then error("schema: no <Schema> element", 0) end
	local id = root.attrs.id
	if not id or id == "" then error("schema: <Schema> needs an id", 0) end
	local self = setmetatable({ id = id, fields = {}, byId = {}, loader = loader }, Schema)
	if root.attrs.extends then
		if not loader then fail(self, "extends " .. root.attrs.extends .. " but has no loader") end
		local base = loader(root.attrs.extends)
		for _, field in ipairs(base.fields) do
			table.insert(self.fields, field)
			self.byId[field.id] = field
		end
	end
	local own = {}
	for _, node in ipairs(root.children) do
		if node.kind == "element" then
			if not TYPES[node.tag] then
				fail(self, "<" .. node.tag .. "> is not a field type; use " ..
					"String, Number, Bool, Bytes, Percent, Date, Symbol, Color, Command, List or Record")
			end
			local fieldId = node.attrs.id
			if not fieldId or fieldId == "" then fail(self, "<" .. node.tag .. "> needs an id") end
			if fieldId:find("[^%w_]") then fail(self, "field id \"" .. fieldId .. "\" must be letters, digits and _") end
			if own[fieldId] then fail(self, "field " .. fieldId .. " is declared twice") end
			own[fieldId] = true
			local field = { id = fieldId, type = node.tag, attrs = node.attrs, states = {}, stateOrder = {} }
			field.source = node.attrs.source or fieldId
			field.writable = node.attrs.writable == "true"
			for _, child in ipairs(node.children) do
				if child.kind == "element" then
					if child.tag ~= "State" then fail(self, "<" .. child.tag .. "> inside " .. fieldId .. "; only <State> is allowed") end
					if not child.attrs.id then fail(self, "a <State> of " .. fieldId .. " needs an id") end
					field.states[child.attrs.id] = child.attrs
					table.insert(field.stateOrder, child.attrs.id)
				end
			end
			if (node.tag == "List" or node.tag == "Record") and not node.attrs.of then
				fail(self, "<" .. node.tag .. "> " .. fieldId .. " needs of=\"Schema\"")
			end
			if node.tag == "Command" and not node.attrs.enabled then field.alwaysEnabled = true end
			if self.byId[fieldId] then
				for index, existing in ipairs(self.fields) do
					if existing.id == fieldId then self.fields[index] = field end
				end
			else
				table.insert(self.fields, field)
			end
			self.byId[fieldId] = field
		end
	end
	self:order()
	return self
end

-- Evaluation order for `format`, so a composed field sees the display value
-- of every field it names; a cycle is an error when the schema loads.
function Schema:order()
	local ordered, state = {}, {}
	local function visit(field)
		if state[field.id] == "done" then return end
		if state[field.id] == "visiting" then fail(self, "format of " .. field.id .. " depends on itself") end
		state[field.id] = "visiting"
		field.refs = {}
		for name in (field.attrs.format or ""):gmatch("%$([%a_][%w_]*)") do
			if name ~= "value" then
				local target = self.byId[name]
				if not target then fail(self, "format of " .. field.id .. " names the undeclared field $" .. name) end
				table.insert(field.refs, name)
				visit(target)
			end
		end
		state[field.id] = "done"
		table.insert(ordered, field)
	end
	for _, field in ipairs(self.fields) do visit(field) end
	self.evaluation = ordered
end

-- A loader reading `<dir>/<id>.xml`. `read(path)` returns the file's text.
function Schema.directory(dir, read, parse)
	local loaded = {}
	local loader
	loader = function(id)
		if loaded[id] == "loading" then error("schema: " .. id .. " extends itself", 0) end
		if loaded[id] then return loaded[id] end
		loaded[id] = "loading"
		local schema = Schema.parse(parse(read(dir .. "/" .. id .. ".xml")), loader)
		if schema.id ~= id then fail(schema, "lives in " .. id .. ".xml; the id must match the file name") end
		loaded[id] = schema
		return schema
	end
	return loader
end

-- The schema named by a List/Record field's `of`.
function Schema:related(field)
	if not self.loader then fail(self, "field " .. field.id .. " names " .. field.attrs.of .. " but has no loader") end
	return self.loader(field.attrs.of)
end

-- ── Validation ─────────────────────────────────────────────────────────

local function read(model, key)
	local value = model[key]
	if type(value) == "function" then return value(model) end
	return value
end

local function truthy(value)
	return value ~= nil and value ~= false and value ~= ""
end
Schema.truthy = truthy

local function setterName(id) return "set" .. id:sub(1, 1):upper() .. id:sub(2) end
Schema.setterName = setterName

-- Problems a model has against this schema, as a list of strings. A field is
-- required unless it declares `missing` or `optional="true"`; a Command needs
-- a method of its name, and a writable field a setter.
function Schema:problems(model)
	local problems = {}
	if type(model) ~= "table" then return { "the model is not a table" } end
	for _, field in ipairs(self.fields) do
		if field.type == "Command" then
			if type(model[field.id]) ~= "function" then
				table.insert(problems, "command " .. field.id .. " has no method " .. field.id)
			end
		else
			local format = field.attrs.format
			local optional = field.attrs.optional == "true" or field.attrs.missing ~= nil or format ~= nil
				or next(field.states) ~= nil
			if model[field.source] == nil and not optional then
				table.insert(problems, "field " .. field.id .. " is missing (model key " .. field.source .. ")")
			end
			if field.writable and type(model[setterName(field.id)]) ~= "function" then
				table.insert(problems, "writable field " .. field.id .. " has no setter " .. setterName(field.id))
			end
		end
	end
	return problems
end

-- Raises when the model lacks a declared field.
function Schema:check(model)
	local problems = self:problems(model)
	if #problems > 0 then
		fail(self, "the model does not satisfy it: " .. table.concat(problems, "; "))
	end
	return model
end

-- ── Projection ─────────────────────────────────────────────────────────

local function digitsOf(field, fallback)
	return tonumber(field.attrs.digits) or fallback
end

local formatters = native()

-- The display string for a raw value of the field's type.
local function convert(field, value, options)
	local type_ = field.type
	if type_ == "Bytes" then
		return formatters._formatBytes(value)
	elseif type_ == "Number" then
		return formatters._formatNumber(value, digitsOf(field, math.floor(value) == value and 0 or 2))
	elseif type_ == "Percent" then
		local digits = digitsOf(field, 0)
		local below = field.attrs.below
		if below and value > 0 and value * 100 < 10 ^ -digits then return below end
		return formatters._formatPercent(value, digits)
	elseif type_ == "Date" then
		return formatters._formatDate(value, field.attrs.style or "medium", options and options.now)
	end
	return tostring(value)
end

-- Projects a model into the record views bind to. `options.now` fixes the
-- clock for relative dates.
function Schema:project(model, options)
	local record = {}
	local display = {}
	for _, field in ipairs(self.evaluation) do
		local id = field.id
		if field.type == "Command" then
			local enabled = field.alwaysEnabled or truthy(read(model, field.attrs.enabled))
			record[id .. ".enabled"] = enabled
		elseif field.type == "List" then
			local rows = read(model, field.source) or {}
			local related = self:related(field)
			local projected = {}
			for _, row in ipairs(rows) do table.insert(projected, related:project(row, options)) end
			record[id] = projected
		elseif field.type == "Record" then
			local nested = read(model, field.source)
			record[id] = nested and self:related(field):project(nested, options) or nil
		else
			local raw = read(model, field.source)
			local active = read(model, field.attrs.state or (id .. "State"))
			if active ~= nil and not field.states[active] then
				fail(self, "field " .. id .. " is in the undeclared state \"" .. tostring(active) .. "\"")
			end
			local text
			if active then
				local state = field.states[active]
				text = state.text or ""
				record[id .. ".icon"], record[id .. ".color"] = state.icon, state.color
				record[id .. ".state"] = active
			elseif raw == nil then
				text = field.attrs.missing or ""
			elseif field.type == "Bool" then
				text = tostring(raw)
			else
				if NUMERIC[field.type] and type(raw) ~= "number" then
					fail(self, "field " .. id .. " is a " .. field.type .. " but the model gives " .. type(raw))
				end
				text = convert(field, raw, options)
			end
			for _, stateId in ipairs(field.stateOrder) do record[id .. "." .. stateId] = stateId == active end
			if field.attrs.format and not (raw == nil and not active and field.attrs.missing) then
				text = (field.attrs.format:gsub("%$([%a_][%w_]*)", function(name)
					if name == "value" then return text end
					return display[name] or ""
				end))
			end
			display[id] = text
			if field.type == "Bool" then
				record[id] = raw == true
			else
				record[id] = text
			end
			if raw ~= nil then record[id .. ".value"] = raw end
			if field.type == "Color" and not active then record[id .. ".color"] = raw end
		end
	end
	return record
end

-- ── Paths ──────────────────────────────────────────────────────────────

-- Resolves a binding path (`{"size", "color"}`) against the schema for a
-- view attribute of `kind`. Returns the record path to read, the field it
-- ends at and that field's schema, or raises. A numeric attribute reads the
-- raw `field.value`; a true/false attribute reads the raw value as well.
function Schema:resolve(path, kind)
	local schema, field = self, nil
	local index = 1
	local prefix = {}
	while index <= #path do
		field = schema.byId[path[index]]
		if not field then
			fail(schema, "binding $" .. table.concat(path, ".") .. " names the undeclared field " .. path[index])
		end
		table.insert(prefix, path[index])
		index = index + 1
		if field.type == "Record" and index <= #path then
			schema = schema:related(field)
			field = nil
		else
			break
		end
	end
	if not field then fail(schema, "binding $" .. table.concat(path, ".") .. " ends at a record; name one of its fields") end
	local rest = {}
	while index <= #path do table.insert(rest, path[index]); index = index + 1 end
	local resolved = { table.unpack(prefix) }
	if field.type == "List" or field.type == "Record" then
		local wanted = field.type == "List" and "rows" or "record"
		if kind ~= wanted then
			fail(schema, "binding $" .. table.concat(path, ".") .. " ends at a " .. field.type:lower() ..
				"; only " .. (field.type == "List" and "items" or "context") .. " binds it")
		end
		if #rest > 0 then fail(schema, "binding $" .. table.concat(path, ".") .. ": a " .. field.type:lower() .. " has no parts") end
		return resolved, field, schema
	end
	if #rest > 0 then
		local suffix = rest[1]
		if #rest > 1 or not (SUFFIXES[suffix] or field.states[suffix]) then
			fail(schema, "binding $" .. table.concat(path, ".") .. ": " .. field.id ..
				" has no part \"" .. table.concat(rest, ".") .. "\"")
		end
		resolved[#resolved] = field.id .. "." .. suffix
		return resolved, field, schema
	end
	if kind == "command" or kind == "field" then return resolved, field, schema end
	if field.type == "Command" then
		fail(schema, "binding $" .. field.id .. " is a command; bind it with action=\"$" .. field.id .. "\"")
	end
	if kind == "number" then
		if not NUMERIC[field.type] then
			fail(schema, "a numeric attribute cannot bind " .. field.type .. " field " .. field.id)
		end
		resolved[#resolved] = field.id .. ".value"
	elseif kind == "bool" and field.type ~= "Bool" then
		resolved[#resolved] = field.id .. ".value"
	end
	return resolved, field, schema
end

-- Reads `path` from a projected record: the longest dotted key first, then
-- down through nested records.
local function lookup(record, path, from)
	for to = #path, from, -1 do
		local value = record[table.concat(path, ".", from, to)]
		if value ~= nil then
			if to == #path then return value end
			if type(value) == "table" then
				local found = lookup(value, path, to + 1)
				if found ~= nil then return found end
			end
		end
	end
	return nil
end

function Schema.lookup(record, path)
	return lookup(record, path, 1)
end

return Schema
