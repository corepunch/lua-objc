local Owners = {}

-- Launch Services resolves bundle identifiers independently of the app's
-- filename or translated display name. An unknown owner never launches a
-- different tool, and a failed launch remains visible to its caller.
local APPLICATIONS = {
	xcode = {id = "com.apple.dt.Xcode", name = "Xcode"},
	docker = {id = "com.docker.docker", name = "Docker"},
	codex = {id = "com.openai.codex", name = "Codex"},
	claude = {id = "com.anthropic.claudefordesktop", name = "Claude"},
}

function Owners.open(owner, execute)
	local app = type(owner) == "string" and APPLICATIONS[owner:lower()]
	if not app then return false, "Unsupported cleanup owner: " .. tostring(owner) .. "." end
	if not execute(app.id) then return false, "Could not open " .. app.name .. ". Check that it is installed and can be opened." end
	return true
end

return Owners
