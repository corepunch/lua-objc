-- API keys live in the keychain, one item per provider under Studio's
-- service name: never in a project folder, which Files shares and Git
-- records. A key is a non-empty string; clearing one removes the item.
local Keys = {}
Keys.__index = Keys

Keys.service = "org.luaobjc.studio"

-- `keychain` is the platform module's `_keychainGet/_keychainSet/_keychainDelete`.
function Keys.new(keychain)
	return setmetatable({ keychain = keychain }, Keys)
end

function Keys:get(provider)
	if type(provider) ~= "string" or provider == "" then return nil end
	local value = self.keychain._keychainGet(Keys.service, provider)
	if type(value) == "string" and value ~= "" then return value end
	return nil
end

function Keys:has(provider)
	return self:get(provider) ~= nil
end

--- Stores `value`; an empty value removes the key.
function Keys:set(provider, value)
	if type(provider) ~= "string" or provider == "" then return nil, "Unknown provider" end
	if type(value) ~= "string" then return nil, "Enter an API key" end
	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" then return self.keychain._keychainDelete(Keys.service, provider) end
	return self.keychain._keychainSet(Keys.service, provider, value)
end

return Keys
