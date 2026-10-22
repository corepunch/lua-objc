-- The Settings sheet: which provider and model the project talks to, and
-- an API key per installed provider. Keys are shown only as present or
-- absent; the field holds what the person is typing now.
local Settings = {}

-- `point` is the provider extension point; `choice` is {provider, model}
-- as the project saved it; `hasKey(id)` asks the keychain; `drafts` maps a
-- provider id to the key typed but not yet saved; `customModel` is a model
-- id typed in place of the list.
function Settings.presentation(point, choice, hasKey, drafts, customModel)
	drafts = drafts or {}
	local providers, selected = {}, nil
	for _, descriptor in ipairs(point:list()) do
		local entry = {
			id = descriptor.id, title = descriptor.title, symbol = descriptor.symbol or "cpu",
			website = descriptor.website or "", keyPrefix = descriptor.keyPrefix or "",
			hasKey = hasKey(descriptor.id), draft = drafts[descriptor.id] or "",
			selected = descriptor.id == choice.provider,
		}
		entry.status = entry.draft ~= "" and "Will be saved" or (entry.hasKey and "Saved in the keychain" or "Not set")
		table.insert(providers, entry)
		if entry.selected then selected = descriptor end
	end
	if not selected and providers[1] then
		providers[1].selected = true
		selected = point:get(providers[1].id)
	end
	local models, providerIndex, modelIndex = {}, 0, nil
	for index, provider in ipairs(providers) do
		if provider.selected then providerIndex = index - 1 end
	end
	local currentModel = customModel or choice.model
	if selected then
		if type(currentModel) ~= "string" or currentModel == "" then currentModel = selected.defaultModel end
		for index, model in ipairs(selected.models) do
			local row = { id = model.id, title = model.title, selected = model.id == currentModel }
			if row.selected then modelIndex = index - 1 end
			table.insert(models, row)
		end
	end
	local custom = modelIndex == nil and currentModel or ""
	if modelIndex == nil then modelIndex = #models end
	return {
		providers = providers,
		providerIndex = providerIndex,
		provider = selected and { id = selected.id, title = selected.title } or nil,
		models = models,
		modelIndex = modelIndex,
		model = currentModel or "",
		customModel = custom,
	}
end

return Settings
