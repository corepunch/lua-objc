local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Files = require("apps.diskmap.models.Files")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Recommendations = {}

local function matches(row, needle)
	return needle == "" or ((row.name or "") .. " " .. (row.subtitle or "") .. " " .. (row.path or "")):lower():find(needle, 1, true) ~= nil
end

local function relative(rows)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.bytes or 0) end
	for _, row in ipairs(rows) do row.relative = largest > 0 and (row.bytes or 0) / largest or 0 end
	return rows
end

-- Every location the knowledge base has an opinion about: cleanup rules and
-- catalog review thresholds. Measured ones below their threshold, kept ones
-- and ones absent from this Mac are reported as checked, so the page shows
-- the whole checklist and not only what crossed a line.
function Recommendations.checked(model, suggested, needle)
	local rows, absent, total = {}, 0, 0
	for _, row in ipairs(model.resources:leaves()) do
		local rule = Rules[row.id]
		local threshold = rule and rule.threshold or row.reviewThreshold
		if threshold and not suggested[row.id] then
			total = total + 1
			local m = model.measurements[row.id] or {}
			if m.status == "complete" and (m.bytes or 0) == 0 then
				absent = absent + 1
			elseif m.bytes and m.bytes > 0 then
				local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
					bytes = m.bytes, size = (m.status == "partial" and "≥ " or "") .. Model.size(m.bytes),
					subtitle = rule and rule.advice or row.consequence or row.subtitle,
					detail = row:isKept() and "Kept" or row.policy == "Essential" and "Essential" or ("Under " .. Model.size(threshold)),
					shareText = ""}
				if matches(value, needle) then table.insert(rows, value) end
			end
		end
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.id < b.id end)
	return relative(rows), absent, total
end

-- The Clean Up page: rebuildable and review suggestions from the cleanup
-- rules, pointers to file- and app-level findings, and the checked list.
-- `apps` is the Applications summary when it has been computed.
function Recommendations.presentation(model, query, apps)
	local needle = (query or ""):lower()
	local rebuildable, review, suggested = {}, {}, {}
	local rebuildableBytes, reviewBytes = 0, 0
	for _, row in ipairs(Cleanup.suggestions(model)) do
		suggested[row.id] = true
		row.detail = row.impact == "Safe/rebuildable" and "Rebuildable" or "Review"
		row.shareText = row.partial and "At least" or ""
		if matches(row, needle) then
			if row.impact == "Safe/rebuildable" then
				table.insert(rebuildable, row); rebuildableBytes = rebuildableBytes + row.bytes
			else
				table.insert(review, row); reviewBytes = reviewBytes + row.bytes
			end
		end
	end
	local elsewhere = {}
	local files = Files.summary(model)
	if files and files.reviewableOldBytes > 0 then
		table.insert(elsewhere, {id = "old-files", name = "Documents unused for a year", page = "files", filter = 2,
			subtitle = files.reviewableOld .. " of your own files over " .. Model.size(require("apps.diskmap.models.Inventory").summary.minimumFileBytes)
				.. " were not opened or changed in a year.",
			icon = "clock.fill", color = "systemOrange", bytes = files.reviewableOldBytes, size = Model.size(files.reviewableOldBytes), detail = "Large Files", shareText = ""})
	end
	local installers, installerBytes = 0, 0
	for _, row in ipairs(Files.rows(model, "Installers & archives")) do
		if row.trashable then installers = installers + 1; installerBytes = installerBytes + row.bytes end
	end
	if installerBytes > 0 then
		table.insert(elsewhere, {id = "installers", name = "Installers & archives", page = "files", filter = 3,
			subtitle = installers .. " disk images, installers and archives in your folders. Once installed or expanded they are rarely needed.",
			icon = "opticaldiscdrive.fill", color = "systemTeal", bytes = installerBytes, size = Model.size(installerBytes), detail = "Large Files", shareText = ""})
	end
	if apps and apps.leftovers and apps.leftovers > 0 then
		table.insert(elsewhere, {id = "leftovers", name = "Possible app leftovers", page = "applications",
			subtitle = apps.leftovers .. " data folders belong to no installed app.",
			icon = "questionmark.folder.fill", color = "systemGray", bytes = apps.leftoverBytes, size = Model.size(apps.leftoverBytes), detail = "Applications", shareText = ""})
	end
	if apps and apps.unused and apps.unused > 0 then
		table.insert(elsewhere, {id = "unused-apps", name = "Apps unused for 6 months", page = "applications", filter = 2,
			subtitle = apps.unused .. " apps and their data. Uninstall the ones you no longer need.",
			icon = "hourglass", color = "systemBlue", bytes = apps.unusedBytes, size = Model.size(apps.unusedBytes), detail = "Applications", shareText = ""})
	end
	local visibleElsewhere = {}
	for _, row in ipairs(elsewhere) do if matches(row, needle) then table.insert(visibleElsewhere, row) end end
	local checked, absent, known = Recommendations.checked(model, suggested, needle)
	return {rebuildable = relative(rebuildable), review = relative(review), elsewhere = relative(visibleElsewhere), checked = checked,
		rebuildableBytes = rebuildableBytes, reviewBytes = reviewBytes, absent = absent, known = known,
		summary = #rebuildable + #review == 0 and "No location has crossed its review threshold."
			or (Model.size(rebuildableBytes) .. " rebuildable · " .. Model.size(reviewBytes) .. " to review")}
end

return Recommendations
