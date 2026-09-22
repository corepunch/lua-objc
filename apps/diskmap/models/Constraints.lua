local Constraints = {}

local function failure(code, message)
	return false, {code = code, message = message}
end

local operations = {
	registration = {
		function(context)
			if type(context.definition) ~= "table" then return failure("malformed_definition", "Resource definition must be a table.") end
			return true
		end,
		function(context)
			local id = context.definition.id
			if type(id) ~= "string" or id == "" then return failure("missing_id", "Resource definitions require a nonempty id.") end
			if id:find("%s") then return failure("invalid_id", "Resource id must not contain whitespace.") end
			return true
		end,
		function(context)
			if context.ids and context.ids[context.definition.id] then return failure("duplicate_id", "Resource id is already registered: " .. context.definition.id) end
			return true
		end,
		function(context)
			if context.definition.path ~= nil and type(context.definition.path) ~= "string" then
				return failure("malformed_definition", "Resource path must be a string.")
			end
			if context.paths and context.definition.path and context.paths[context.definition.path] then
				return failure("duplicate_path", "Resource path is already registered: " .. context.definition.path)
			end
			return true
		end,
		function(context)
			local children = context.definition.children
			if children ~= nil and type(children) ~= "table" then return failure("malformed_definition", "Resource children must be an array.") end
			if children then
				for index, child in ipairs(children) do
					if type(child) ~= "table" then return failure("malformed_definition", "Resource child " .. index .. " must be a definition.") end
				end
			end
			return true
		end,
		function(context)
			if context.definition.parentId ~= nil and context.definition.parentId ~= context.parentId then
				return failure("parent_mismatch", "Resource parentId does not match its registered parent.")
			end
			return true
		end,
	},
	keep = {
		function(context)
			if not context.row then return failure("unknown_resource", "Resource is not registered.") end
			return true
		end,
	},
	trash = {
		function(context)
			if not context.row then return failure("unknown_resource", "Resource is not registered.") end
			return true
		end,
		function(context)
			if not context.row:isLeaf() then return failure("not_leaf", "Only a measured leaf resource can be moved to Trash.") end
			return true
		end,
		function(context)
			if context.action ~= "trash" or context.row.action ~= "trash" then return failure("invalid_action", "Resource does not authorize moving to Trash.") end
			return true
		end,
		function(context)
			local path = context.row.path
			if type(path) ~= "string" or path == "" or path:sub(1, 1) ~= "/" or path:find("\0", 1, true) then
				return failure("invalid_path", "Trash requires a nonempty absolute path.")
			end
			return true
		end,
		function(context)
			local measurement = context.row:getMeasurement()
			if type(measurement) ~= "table" or measurement.status ~= "complete" then
				return failure("measurement_incomplete", "A complete measurement is required before moving to Trash.")
			end
			return true
		end,
		function(context)
			local bytes = context.row:getMeasurement().bytes
			if type(bytes) ~= "number" or bytes <= 0 then return failure("measurement_nonpositive", "A positive measured allocation is required before moving to Trash.") end
			return true
		end,
		function(context)
			if context.row:isKept() then return failure("kept_resource", "Keep protects this resource or one of its ancestors.") end
			return true
		end,
	},
	empty = {
		function(context)
			if not context.row then return failure("unknown_resource", "Resource is not registered.") end
			return true
		end,
		function(context)
			if not context.row:isLeaf() then return failure("not_leaf", "Only a measured leaf resource can authorize emptying Trash.") end
			return true
		end,
		function(context)
			if context.action ~= "empty" or context.row.action ~= "empty" then return failure("invalid_action", "Resource does not authorize emptying Trash.") end
			return true
		end,
		function(context)
			local path = context.row.path
			if type(path) ~= "string" or path == "" or path:sub(1, 1) ~= "/" or path:find("\0", 1, true) then
				return failure("invalid_path", "Emptying Trash requires a nonempty absolute path.")
			end
			return true
		end,
		function(context)
			local measurement = context.row:getMeasurement()
			if type(measurement) ~= "table" or measurement.status ~= "complete" then
				return failure("measurement_incomplete", "A complete measurement is required before emptying Trash.")
			end
			return true
		end,
		function(context)
			local bytes = context.row:getMeasurement().bytes
			if type(bytes) ~= "number" or bytes <= 0 then return failure("measurement_nonpositive", "Trash is already empty.") end
			return true
		end,
		function(context)
			if context.row:isKept() then return failure("kept_resource", "Keep protects this resource or one of its ancestors.") end
			return true
		end,
	},
}

function Constraints.evaluate(operation, context)
	local validators = operations[operation]
	if not validators then return failure("unknown_operation", "Unknown constraint operation: " .. tostring(operation)) end
	for _, validate in ipairs(validators) do
		local ok, err = validate(context or {})
		if not ok then return false, err end
	end
	return true
end

Constraints.operations = operations
return Constraints
