_G.__headless = true
-- The knowledge base is one dictionary: every catalog entry says what it is
-- (nature), who removes it (remover), when Clean Up suggests it (threshold)
-- and how (advice). Clean Up sections follow from the remover, and nothing
-- a rule says widens what Diskmap may delete.
local t = require("TestKit")
local Store = require("apps.diskmap.Store")
local Locations = require("apps.diskmap.models.Locations")
local Suggestions = require("apps.diskmap.models.Suggestions")
local Guide = require("apps.diskmap.helpers.Guide")
local Map = require("apps.diskmap.knowledge.Filesystem")

local home = "/Users/test"
local model = Store.new(home)

-- Every leaf uses the vocabulary, carries exactly one advice text and no
-- field from the old rule tables.
local leaves, withThreshold = 0, 0
for _, row in ipairs(Locations:leaves()) do
	leaves = leaves + 1
	t.expect(Locations.natures[row.nature], row.id .. " has a known nature: " .. tostring(row.nature))
	t.expect(Locations.removers[row.remover], row.id .. " has a known remover: " .. tostring(row.remover))
	t.expect(row.reviewThreshold == nil and row.consequence == nil, row.id .. " carries no legacy rule field")
	if row.threshold then
		withThreshold = withThreshold + 1
		t.expect(type(row.advice) == "string" and #row.advice > 20, row.id .. " has one advice text once it has a threshold")
		t.expect(row.remover ~= "none", row.id .. " names who removes it once it has a threshold")
	end
	-- Diskmap's deletion authority is exactly the remover: only trash entries
	-- can be moved to the Trash, only commands run, and policy follows.
	if row.remover == "trash" then t.assertEqual(row.action, "trash", row.id .. " trash remover moves to the Trash") end
	if row.remover == "ownerCommand" then t.expect(row.action == "ownerCleanup" and row.commandId, row.id .. " owner command names its command") end
	if row.action == "trash" then t.assertEqual(row.remover, "trash", row.id .. " may only be trashed when its remover says so") end
	if row.policy == "Rebuildable" then t.expect(row.remover == "trash" or row.remover == "ownerCommand", row.id .. " is Rebuildable only when Diskmap clears it") end
	if row.nature == "system" and row.policy ~= "Essential" then t.assertEqual(row.policy, "System managed", row.id .. " system data is system managed") end
	if (row.nature == "cache" or row.nature == "build") and (row.remover == "trash" or row.remover == "ownerCommand") then
		t.expect(row.threshold ~= nil, row.id .. " cache Diskmap clears has a threshold")
	end
end
t.expect(leaves > 300 and withThreshold > 120, "the dictionary is wide: " .. leaves .. " leaves, " .. withThreshold .. " with thresholds")

-- Sections follow from the remover; the reader's own data is always a decision.
t.assertEqual(Suggestions.section({nature = "cache", remover = "trash"}), "now", "Diskmap-trashed caches clear now")
t.assertEqual(Suggestions.section({nature = "cache", remover = "ownerCommand"}), "now", "owner commands clear now")
t.assertEqual(Suggestions.section({nature = "cache", remover = "owner"}), "app", "app-cleared caches clear in the app")
t.assertEqual(Suggestions.section({nature = "download", remover = "setting"}), "app", "System Settings removals clear in the app")
t.assertEqual(Suggestions.section({nature = "leftover", remover = "restart"}), "restart", "restart-cleared data has its own section")
t.assertEqual(Suggestions.section({nature = "leftover", remover = "update"}), "restart", "update staging is cleared by finishing the update")
t.assertEqual(Suggestions.section({nature = "personal", remover = "owner"}), "decisions", "personal data is a decision whoever removes it")
t.assertEqual(Suggestions.section({nature = "log", remover = "finder"}), "decisions", "what you remove in Finder is a decision")

-- Measure every thresholded location at its threshold: nothing from a
-- system-managed location reaches a cleanup section, and every section
-- appears.
for _, row in ipairs(Locations:leaves()) do
	if row.threshold and not row.artifact then model.measurements[row.id] = {bytes = row.threshold, status = "complete"} end
	if row.nature == "system" and row.remover == "none" then model.measurements[row.id] = {bytes = 50e9, status = "complete"} end
end
local data = Suggestions:presentation()
for _, section in ipairs(Suggestions.sections) do
	t.expect(#data[section] > 0, "the " .. section .. " section has suggestions")
	for _, row in ipairs(data[section]) do
		local location = Locations:find(row.id)
		t.expect(not location or location.remover ~= "none", row.id .. " in " .. section .. " has a remover")
		t.expect(not location or not (location.nature == "system" and location.remover == "none"), row.id .. " is never a system-managed suggestion")
		t.assertEqual(row.section, section, row.id .. " knows its section")
	end
end
t.expect(#data.context > 0, "system-managed storage is context")
local byId = {}
for _, section in ipairs(Suggestions.sections) do for _, row in ipairs(data[section]) do byId[row.id] = section end end
for _, id in ipairs({"pnpm-store", "yarn-cache", "swiftpm-cache", "flutter-pub", "derived", "npm", "mail-downloads"}) do
	t.assertEqual(byId[id], "now", id .. " is cleared now")
end
for _, id in ipairs({"spotify-cache", "chrome-cache", "adobe-media-cache", "user-caches", "devices", "voices-1", "aerials"}) do
	t.assertEqual(byId[id], "app", id .. " is cleared in its app or in Settings")
end
for _, id in ipairs({"tmp", "temporary", "vm", "update-brain", "install-data"}) do
	t.assertEqual(byId[id], "restart", id .. " is cleared by a restart or the pending update")
end
for _, id in ipairs({"downloads", "photos-library", "whatsapp", "device-backups", "user-trash", "user-logs", "brew-logs",
	"steam-games", "ollama", "logic-sound-library", "spotify-downloads", "nvm", "unity-editors"}) do
	t.assertEqual(byId[id], "decisions", id .. " is the reader's decision")
end
for _, id in ipairs({"siri-assets-1", "dictation-1", "foundation-models-7", "mobile-assets", "codex-plugins", "runtime-images"}) do
	t.assertEqual(byId[id], nil, id .. " is never suggested")
end
t.expect(data.lead ~= nil and data.count > 100, "the lead is the best suggestion of any section")

-- Rows carry a status by section, and the lead verb follows the remover.
local statuses = {now = "arrow.triangle.2.circlepath.circle.fill", app = "arrow.up.forward.app.fill", restart = "power.circle.fill", decisions = "eye.circle.fill"}
for section, icon in pairs(statuses) do
	for _, row in ipairs(data[section]) do
		if not row.page then t.assertEqual(row.statusIcon, icon, row.id .. " shows the " .. section .. " symbol"); break end
	end
end

-- Eligibility: Diskmap-cleared caches are sure, app- and restart-cleared
-- regenerable data is probable, personal data is unknown.
local function found(id) for _, section in ipairs(Suggestions.sections) do for _, row in ipairs(data[section]) do if row.id == id then return row end end end end
-- Content the reader chose is never claimed recoverable: only they know
-- what they still play, run or listen to.
for _, row in ipairs(Locations:leaves()) do
	if row.nature == "library" then
		t.expect(row.remover == "owner" or row.remover == "finder", row.id .. " library content is removed by its app or in Finder")
		local suggestion = found(row.id)
		t.expect(not suggestion or suggestion.eligibleBytes == nil, row.id .. " claims no recoverable bytes")
	end
end
t.expect(found("derived").eligibleBytes == 1e9 and found("derived").confidence == "High", "a trashed cache is fully recoverable with high confidence")
t.expect(found("spotify-cache").eligibleBytes == 500e6 and found("spotify-cache").confidence == "Medium", "an app-cleared cache is recoverable with medium confidence")
t.expect(found("tmp").eligibleBytes == 1e9 and found("tmp").effort == "Low", "a restart recovers temporary files at low effort")
t.expect(found("downloads").eligibleBytes == nil and found("downloads").shareText == "to review", "personal files are bytes to review")

-- The map's leftovers become leftover entries with their remover; /tmp
-- is cleared by a restart and the update stagings by finishing the update.
t.assertEqual(Locations:find("tmp").path, "/private/tmp", "tmp is the real /private/tmp")
t.assertEqual(Locations:find("tmp").remover, "restart", "a restart empties /tmp")
t.assertEqual(Locations:find("data-update-staging").remover, "update", "update staging is finished, not deleted")
for _, area in ipairs(Map.areas) do
	for _, location in ipairs(area.locations) do
		if location.leftover then
			t.expect(Locations.removers[location.leftover.remover] and location.leftover.remover ~= "none", location.leftover.id .. " names its remover")
		end
	end
end

-- The Storage Guide borrows advice from the catalog instead of restating it.
t.assertEqual(Guide.action(Guide.topic("derived-data"), Locations.advice), Locations:find("derived").advice, "the DerivedData topic shows the catalog advice")
t.assertEqual(Guide.action(Guide.topic("vm"), Locations.advice), Locations:find("vm").advice, "the swap topic shows the catalog advice")
t.expect(Guide.topic("container").action ~= nil and Guide.action(Guide.topic("container"), Locations.advice) == Guide.topic("container").action, "a topic without a location keeps its own action")
for _, chapter in ipairs(Guide.chapters) do
	for _, topic in ipairs(chapter.topics) do
		t.expect(Guide.action(topic, Locations.advice) ~= nil, "every guide topic has an action: " .. topic.id)
	end
end

os.exit(t.summary() and 0 or 1)
