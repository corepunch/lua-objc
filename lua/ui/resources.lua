-- XML resources: the constants a template used to keep in a Lua table at its
-- top (`local COLUMNS = {...}`), declared as data, like a WPF
-- ResourceDictionary.
--
--   <Resources>
--   	<Number id="symbolColumn" value="26" />
--   	<String id="unit" value="GB" />
--   	<Bool id="compact" value="true" />
--   	<Color id="accent" value="systemBlue" />
--   </Resources>
--
-- An attribute written `@name` takes the resource's value, resolved once
-- when the template renders (`$name` is live data, `@name` is static).
-- An attribute is a literal or exactly one reference, so a resource cannot be
-- spliced into a longer string. `@` is a reference only where some resources
-- are in scope, and there an undeclared name is an error.
--
-- Scope follows the tree. The app's resources (`resources.xml`, passed to a
-- render as `data.resources`) apply everywhere; a `<Resources>` element
-- applies to the subtree of its parent and overrides what it inherits, as
-- `Panel.Resources` does in WPF. The element itself never becomes a view.
local Resources = {}

local KINDS = {
	Number = function(value, id)
		if tonumber(value) == nil then
			error("resources: <Number> " .. id .. " has the non-numeric value \"" .. tostring(value) .. "\"", 0)
		end
		return tostring(tonumber(value))
	end,
	String = function(value) return value end,
	Color = function(value) return value end,
	Bool = function(value, id)
		if value ~= "true" and value ~= "false" then
			error("resources: <Bool> " .. id .. " must be true or false, not \"" .. tostring(value) .. "\"", 0)
		end
		return value
	end,
}

-- Reads the declarations of one <Resources> node into `into` (name -> the
-- value as attribute text).
local function declare(node, into)
	for _, child in ipairs(node.children) do
		if child.kind == "element" then
			local convert = KINDS[child.tag]
			if not convert then
				error("resources: <" .. child.tag .. "> is not a resource; use Number, String, Bool or Color", 0)
			end
			local id, value = child.attrs.id, child.attrs.value
			if not id or id == "" then error("resources: <" .. child.tag .. "> needs an id", 0) end
			if value == nil then error("resources: <" .. child.tag .. "> " .. id .. " needs a value", 0) end
			if rawget(into, id) ~= nil then
				error("resources: " .. id .. " is declared twice in one <Resources>", 0)
			end
			into[id] = convert(value, id)
		end
	end
	return into
end

-- Parsed XML nodes of a <Resources> document -> name -> value.
function Resources.fromNodes(nodes)
	local scope = {}
	local found = false
	for _, node in ipairs(nodes) do
		if node.kind == "element" then
			if node.tag ~= "Resources" then
				error("resources: the document root must be <Resources>, not <" .. node.tag .. ">", 0)
			end
			declare(node, scope)
			found = true
		end
	end
	if not found then error("resources: no <Resources> element", 0) end
	return scope
end

-- The scope a list of siblings sees: `scope` plus what its <Resources>
-- elements declare.
-- Marks a scope that has resources in it. Without any, `@` is ordinary text
-- (a path like node_modules/@img reaches attributes as data).
local ANY = " any"
local function extend(list, scope)
	local own
	for _, node in ipairs(list) do
		if node.kind == "element" and node.tag == "Resources" then
			own = own or setmetatable({ [ANY] = true }, { __index = scope })
			declare(node, own)
		end
	end
	return own or scope
end

-- Replaces `@name` attributes in `nodes` (in place) and removes <Resources>
-- elements, which scope their declarations to the parent element: its own
-- attributes and its whole subtree. At the top of a template they apply to
-- every root.
function Resources.resolve(nodes, inherited)
	local function visit(list, scope)
		scope = extend(list, scope)
		local kept = {}
		for _, node in ipairs(list) do
			if node.kind ~= "element" or node.tag ~= "Resources" then
				if node.kind == "element" then
					local own = extend(node.children, scope)
					for key, value in pairs(node.attrs) do
						local name = type(value) == "string" and own[ANY] and value:match("^@([%a_][%w_]*)$")
						if name then
							local resolved = own[name]
							if resolved == nil then
								error("xml: <" .. node.tag .. "> " .. key .. "=\"" .. value
									.. "\" names a resource that is not declared", 0)
							end
							node.attrs[key] = resolved
						end
					end
					node.children = visit(node.children, own)
				end
				table.insert(kept, node)
			end
		end
		return kept
	end
	if inherited and next(inherited) ~= nil and not inherited[ANY] then
		inherited = setmetatable({ [ANY] = true }, { __index = inherited })
	end
	return visit(nodes, inherited or {})
end

return Resources
