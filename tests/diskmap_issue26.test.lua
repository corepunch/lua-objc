_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local Inspector = require("apps.diskmap.models.Inspector")
local Rules = require("apps.diskmap.knowledge.CleanupRules")

local home = "/Users/test"
local model = Model.new(home)
local function resource(id)
	local row = model.resources:find(id)
	t.expect(row ~= nil, "catalog contains " .. id)
	return row
end

-- Each added category has one measured owner path and owner-managed guidance.
local adobe = resource("adobe-media-cache")
t.assertEqual(adobe.path, home .. "/Library/Application Support/Adobe/Common/Media Cache Files", "shared Adobe media cache uses its documented default path")
t.assertEqual(adobe.action, "finder", "Adobe cache remains owner reviewed")
t.assertEqual(adobe.policy, "Review", "Adobe cache stays review only")
t.expect(adobe.consequence:find("customized", 1, true) ~= nil, "Adobe guidance discloses custom cache locations")
local afterEffects = resource("adobe-caches")
t.assertEqual(afterEffects.path, home .. "/Library/Caches/Adobe", "Adobe application cache uses the documented default root")
t.assertEqual(afterEffects.action, "finder", "Adobe application caches are not deleted by Diskmap")

local mailLogs = resource("mail-logs")
t.assertEqual(mailLogs.path, home .. "/Library/Containers/com.apple.mail/Data/Library/Logs/Mail", "Mail diagnostic logs have their own exact path")
t.assertEqual(mailLogs.action, "finder", "Mail logs remain owner reviewed")
t.expect(mailLogs.consequence:find("turn off", 1, true) ~= nil, "Mail guidance stops logging before review")
t.expect(resource("mail").path ~= mailLogs.path, "Mail logs stay separate from saved messages")

-- No dependable signal or owner flow supports separate recording, Docker-log,
-- or IPSW resources; the existing broader locations remain the inventory.
t.assertEqual(model.resources:find("screen-recordings"), nil, "personal recordings are not inferred from names or extensions")
t.assertEqual(model.resources:find("docker-logs"), nil, "Docker logs are not assigned an unmeasurable host path")
t.assertEqual(model.resources:find("ios-restore-images"), nil, "restore images are not assigned a guessed hidden path")
t.assertEqual(model.resources:find("ipsw"), nil, "IPSW files have no invented catalog location")

local movies = resource("movies")
t.assertEqual(movies.path, home .. "/Movies", "known media library keeps its actual owner path")
t.expect(movies.mediaAccess, "personal media remains behind the explicit media opt-in")
local paths, ids = Inventory.plan(model)
local included = {}
for index, id in ipairs(ids) do included[id] = paths[index] end
t.assertEqual(included.movies, nil, "Movies is excluded by default")
t.assertEqual(model.measurements.movies.status, "excluded", "excluded media is not reported as zero")
model.includeMedia = true
paths, ids = Inventory.plan(model)
included = {}
for index, id in ipairs(ids) do included[id] = paths[index] end
t.assertEqual(included.movies, home .. "/Movies", "explicit media opt-in measures the configured Movies library")

local docker = resource("docker")
t.assertEqual(docker.path, home .. "/Library/Containers/com.docker.docker", "Docker keeps one measured default aggregate")
t.assertEqual(docker.action, "docker", "Docker review opens the owner app")
t.assertEqual(docker.policy, "Review", "Docker data remains review only")
t.expect(docker.consequence:find("custom location", 1, true) ~= nil, "Docker guidance warns that a moved disk may be outside the measured path")
t.expect(docker.consequence:find("not separately measured", 1, true) ~= nil, "Docker guidance does not promise per-container log sizes")
t.expect(Rules.docker.advice:find("per-container allocation", 1, true) ~= nil, "Docker cleanup advice explains the log measurement boundary")

for _, id in ipairs({"movies", "downloads", "device-backups", "docker", "mail-logs", "adobe-media-cache", "adobe-caches"}) do
	local row = resource(id)
	model.measurements[id] = {bytes = 20e9, status = "complete"}
	local valid, failure = row:validateTrash()
	t.expect(not valid and failure.code == "invalid_action", id .. " remains outside Diskmap's deletion authority")
end

local dockerDetails = Inspector.details(model, "docker")
t.expect(dockerDetails.canManage and dockerDetails.manageTitle == "Open Docker", "Docker inspector offers owner review without a cleanup action")

os.exit(t.summary() and 0 or 1)
