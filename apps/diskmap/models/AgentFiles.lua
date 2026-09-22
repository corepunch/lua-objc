local AgentFiles = {}
-- Metadata only: recognize versioned SQLite sidecars without opening credentials or history.
function AgentFiles.add(model, entries)
	local paths = {}; for _, row in ipairs(model.leaves) do if row.path then paths[row.path] = true end end
	for _, entry in ipairs(entries or {}) do
		local parent = model.byId[entry.agent]
		if parent and parent.children and entry.path and not paths[entry.path] then
			local name = entry.name or ""
			local directories = {node_repl = "Tool runtime", attachments = "Generated assets", browser = "Browser data", ["computer-use"] = "Generated assets", tmp = "Temporary data", [".tmp"] = "Temporary data", vendor_imports = "Plugins", memories = "Sessions & memory", ["dictation-history"] = "Sessions & history", rules = "Settings", automations = "Settings"}
			local kind = name:match("%.sqlite") or name:match("%.db")
			kind = kind and "Database" or name:match("%.jsonl$") and "History" or (name:match("%.toml$") or name:match("%.json$")) and "Settings"
			kind = kind or directories[name] or "Unclassified"
			if kind then
				local row = {id = entry.agent .. "-file-" .. name, name = kind .. " · " .. name,
					subtitle = "Persistent tool state; review only", path = entry.path, parentId = parent.id,
					policy = "Review", action = "finder", agent = entry.agent, icon = parent.icon, color = parent.color}
				parent.children[#parent.children + 1] = row; model.leaves[#model.leaves + 1] = row
				model.byId[row.id] = row; paths[row.path] = true
			end
		end
	end
end
return AgentFiles
