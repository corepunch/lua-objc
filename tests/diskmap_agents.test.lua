_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local AgentFiles = require("apps.diskmap.models.AgentFiles")

local model = Model.new("/Users/test")
local function check(id, path, action, policy)
	local row = model.resources:find(id)
	t.expect(row ~= nil, "agent resource is registered: " .. id)
	t.assertEqual(row.path, path, "agent resource measures the verified location: " .. id)
	t.assertEqual(row.action, action, "agent resource has a safe action: " .. id)
	t.assertEqual(row.policy, policy, "agent resource states its policy: " .. id)
end
check("codex-sessions", "/Users/test/.codex/sessions", "finder", "Review")
check("codex-archives", "/Users/test/.codex/archived_sessions", "finder", "Review")
check("codex-worktrees", "/Users/test/.codex/worktrees", "finder", "Review")
check("codex-cache", "/Users/test/.codex/cache", "trash", "Rebuildable")
check("opencode-snapshots", "/Users/test/.local/share/opencode/snapshot", "finder", "Review")
check("opencode-logs", "/Users/test/.local/share/opencode/log", "finder", "Review")
check("claude-projects", "/Users/test/.claude/projects", "finder", "Review")
check("claude-history", "/Users/test/.claude/file-history", "finder", "Review")
check("claude-cache", "/Users/test/.claude/cache", "trash", "Rebuildable")
check("cursor-cache", "/Users/test/Library/Application Support/Cursor/Cache", "trash", "Rebuildable")
check("grok-cache", "/Users/test/.grok/cache", "trash", "Rebuildable")
t.assertEqual(model.resources:find("codex-models"), nil, "speculative codex models are gone")
t.assertEqual(model.resources:find("codex-databases"), nil, "speculative codex sqlite dir is gone")
t.assertEqual(model.resources:find("opencode-models"), nil, "speculative opencode models are gone")
t.assertEqual(model.resources:find("opencode-settings"), nil, "speculative opencode config row is gone")
t.expect(model.resources:find("claude") ~= nil and not model.resources:find("claude"):isLeaf(), "claude is a group with measured children")

local added, addError = AgentFiles.add(model, {
	{agent = "claude", name = "debug.log", path = "/Users/test/.claude/debug.log"},
	{agent = "claude", name = "settings.json", path = "/Users/test/.claude/settings.json"},
	{agent = "codex", name = "logs_2.sqlite", path = "/Users/test/.codex/logs_2.sqlite"},
})
t.assertEqual(added, true, "discovered agent files register: " .. tostring(addError))
t.assertEqual(model.resources:find("claude-file-debug.log").name, "Logs · debug.log", "debug logs classify as logs")
t.assertEqual(model.resources:find("claude-file-settings.json").name, "Settings · settings.json", "settings classify as settings")
t.assertEqual(model.resources:find("codex-file-logs_2.sqlite").name, "Database · logs_2.sqlite", "diagnostic databases classify as databases")
t.assertEqual(model.resources:find("codex-file-logs_2.sqlite").action, "finder", "diagnostic databases stay review-only")

model.measurements["codex-sessions"] = {bytes = 2e9, status = "complete"}
model.measurements["claude-cache"] = {bytes = 600e6, status = "complete"}
model.measurements["opencode-snapshots"] = {bytes = 3e9, status = "complete"}
local suggestions = Cleanup.suggestions(model)
local byId = {}
for _, suggestion in ipairs(suggestions) do byId[suggestion.id] = suggestion end
t.expect(byId["codex-sessions"] ~= nil, "large session history surfaces for review")
t.expect(byId["codex-sessions"].subtitle:find("Codex", 1, true) ~= nil, "session advice names the owning tool")
t.assertEqual(byId["codex-sessions"].impact, "Needs review", "session history is never safe/rebuildable")
t.expect(byId["claude-cache"] ~= nil, "large tool cache surfaces for review")
t.assertEqual(byId["claude-cache"].impact, "Safe/rebuildable", "tool cache is safe/rebuildable")
t.expect(byId["opencode-snapshots"] ~= nil, "large snapshot storage surfaces for review")
t.expect(byId["opencode-snapshots"].subtitle:find("orphaned", 1, true) ~= nil, "snapshot advice names the orphan risk")
t.assertEqual(byId["opencode-snapshots"].action, "finder", "snapshot storage stays review-only")

os.exit(t.summary() and 0 or 1)
