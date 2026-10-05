-- Components: new XML tags written as etlua templates, the way `partial()`
-- reuses view structure, but used like any other tag:
--
--   <CapacityBar total="500" maxWidth="infinity">
--     <CapacitySegment value="180" color="systemBlue" />
--   </CapacityBar>
--
-- A component is `<Tag>.etlua` in a `components/` folder. Before a template
-- is compiled, each component tag is replaced by the elements its template
-- renders, so a component is ordinary template content: the XML renderer
-- stays the only caller of view constructors, and retained templates
-- reconcile a component's views like any others.
--
-- An optional `<Tag>.lua` beside the template declares what the tag takes:
--
--   return {
--   	props = { total = "num", spacing = { type = "num", default = 1 } },
--   	records = { CapacitySegment = { value = "num", color = "str" } },
--   	data = function(props, records, attrs) return { segments = ... } end,
--   }
--
-- `props` are the attributes handed to the template, typed "num", "bool" or
-- "str"; `records` the child tags read as data rather than views; `data`
-- returns further template variables computed from them (geometry belongs
-- here, in plain functions tests can call). `attrs` holds every attribute as
-- written, for geometry that depends on the frame. The module never touches
-- views.
--
-- Every attribute that is not a declared prop (`id`, `width`, `maxWidth`,
-- `padding`, `transition`, `accessibilityLabel`...) goes to the template's
-- single root element, over the root's own. View children replace the
-- template's `<ContentPresenter />`.
--
-- Resolution: the `components/` folder nearest the template using the tag
-- (an app's `components/` beside its `views/`), then the framework's
-- `lua/components/`. Built-in tags are never components.
local Component = {}

local BUNDLED = "lua/components/"
local SLOT = "ContentPresenter"
-- A component that uses itself would expand forever.
local LIMIT = { depth = 32 }

local function coerce(value, kind)
	if value == nil then return nil end
	if kind == "num" then return tonumber(value) end
	if kind == "bool" then return value == true or value == "true" or value == "1" end
	return value
end

-- `attrs` read through `schema` ({ name = "num" | { type =, default = } }).
local function typed(schema, attrs)
	local result = {}
	for name, spec in pairs(schema or {}) do
		local kind, default = spec, nil
		if type(spec) == "table" then kind, default = spec.type, spec.default end
		local value = coerce(attrs[name], kind)
		if value == nil then value = default end
		result[name] = value
	end
	return result
end

-- Folders that may hold components for a template in `baseDir`, nearest
-- first: each ancestor's components/, then the bundled set.
function Component.folders(baseDir)
	local folders, seen = {}, {}
	local dir = tostring(baseDir or ""):gsub("\\", "/")
	local root = dir:match("^/") and "/" or ""
	local parts = {}
	for part in dir:gmatch("[^/]+") do
		if part ~= "." then table.insert(parts, part) end
	end
	local function add(folder)
		if not seen[folder] then seen[folder] = true; table.insert(folders, folder) end
	end
	for count = #parts, 0, -1 do
		local prefix = table.concat(parts, "/", 1, count)
		add(root .. (prefix ~= "" and prefix .. "/" or "") .. "components/")
	end
	add(BUNDLED)
	return folders
end

-- Where a tag was found from a folder, so later uses read two files instead
-- of probing every ancestor; and each module's value for its source, so a
-- module runs again only when it was edited.
local located, modules = {}, {}

local function moduleAt(path, chunk)
	local cached = modules[path]
	if cached and cached.chunk == chunk then return cached.value end
	local value = assert(load(chunk, "@" .. path))()
	assert(type(value) == "table", "component " .. path .. " must return a table")
	modules[path] = { chunk = chunk, value = value }
	return value
end

local function read(tag, folder)
	local xml = require("ui.xml")
	local source = xml.source(folder .. tag .. ".etlua")
	if not source then return nil end
	local chunk = xml.source(folder .. tag .. ".lua")
	return { tag = tag, dir = folder, source = source, path = folder .. tag .. ".etlua",
		module = chunk and moduleAt(folder .. tag .. ".lua", chunk) or {} }
end

-- The component for `tag` near `baseDir`: { tag, dir, source, module }, or
-- nil. Sources are read on every use, so an edited component takes effect
-- on the next render.
function Component.find(tag, baseDir)
	if type(tag) ~= "string" or not tag:match("^%u[%w]*$") then return nil end
	local key = tostring(baseDir or "") .. "\0" .. tag
	local component = located[key] and read(tag, located[key])
	if component then return component end
	for _, folder in ipairs(Component.folders(baseDir)) do
		component = read(tag, folder)
		if component then
			located[key] = folder
			return component
		end
	end
	located[key] = nil
	return nil
end

local function elements(nodes)
	local result = {}
	for _, node in ipairs(nodes) do if node.kind == "element" then table.insert(result, node) end end
	return result
end

-- Replaces the slot in `nodes` with `content`; returns whether it was found.
local function present(nodes, content)
	for index, node in ipairs(nodes) do
		if node.kind == "element" then
			if node.tag == SLOT then
				table.remove(nodes, index)
				for offset, child in ipairs(content) do table.insert(nodes, index + offset - 1, child) end
				return true
			end
			if present(node.children, content) then return true end
		end
	end
	return false
end

local expand

-- The element a component tag `node` stands for.
local function instantiate(node, component, isBuiltin, depth)
	if depth > LIMIT.depth then error("component <" .. node.tag .. "> uses itself") end
	local xml = require("ui.xml")
	local module = component.module
	local records, content = {}, {}
	for _, child in ipairs(elements(node.children)) do
		local schema = module.records and module.records[child.tag]
		if schema then
			local record = typed(schema, child.attrs)
			record.tag = child.tag
			table.insert(records, record)
		else
			table.insert(content, child)
		end
	end
	local props = typed(module.props, node.attrs)
	local data = { records = records }
	for name, value in pairs(props) do data[name] = value end
	if module.data then
		for name, value in pairs(module.data(props, records, node.attrs) or {}) do data[name] = value end
	end
	data.__baseDir = component.dir
	local rendered = xml.parse(xml.describe(component.source, data, component.path).source)
	local roots = elements(rendered)
	if #roots ~= 1 then
		error("component <" .. node.tag .. "> must render one root element, not " .. #roots)
	end
	local root = roots[1]
	if root.tag == SLOT then error("component <" .. node.tag .. "> needs a root element around its content") end
	if not present(root.children, content) and #content > 0 then
		error("component <" .. node.tag .. "> takes no content: <" .. content[1].tag .. ">")
	end
	for name, value in pairs(node.attrs) do
		if not (module.props and module.props[name] ~= nil) then root.attrs[name] = value end
	end
	-- The component's own tags resolve from its folder.
	return expand({ root }, component.dir, isBuiltin, depth + 1)[1]
end

expand = function(nodes, baseDir, isBuiltin, depth)
	for index, node in ipairs(nodes) do
		if node.kind == "element" then
			local component = not isBuiltin(node.tag) and Component.find(node.tag, baseDir)
			if component then
				-- Content belongs to the template that wrote it; records
				-- are data and hold no tags to resolve.
				local records = component.module.records or {}
				for position, child in ipairs(node.children) do
					if child.kind == "element" and not records[child.tag] then
						node.children[position] = expand({ child }, baseDir, isBuiltin, depth)[1]
					end
				end
				nodes[index] = instantiate(node, component, isBuiltin, depth)
			else
				expand(node.children, baseDir, isBuiltin, depth)
			end
		end
	end
	return nodes
end

--- Replaces every component tag in parsed `nodes` with the elements its
--- template renders. `isBuiltin(tag)` names the tags of the vocabulary.
function Component.expand(nodes, baseDir, isBuiltin)
	return expand(nodes, baseDir, isBuiltin, 1)
end

return Component
