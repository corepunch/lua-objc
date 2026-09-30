local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Files = require("apps.diskmap.models.Files")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Status = require("apps.diskmap.models.Status")
local Tips = require("apps.diskmap.models.Tips")
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
		-- Build folders are checked as their ecosystem's group.
		if row.artifact then threshold = nil end
		if threshold and not suggested[row.id] then
			total = total + 1
			local m = model.measurements[row.id] or {}
			if m.status == "complete" and (m.bytes or 0) == 0 then
				absent = absent + 1
			elseif m.bytes and m.bytes > 0 then
				local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
					bytes = m.bytes,
					subtitle = rule and rule.advice or row.consequence or row.subtitle,
					detail = row:isKept() and "Kept" or row.policy == "Essential" and "Essential" or ("Under " .. Model.size(threshold)),
					shareText = ""}
				Model.sizeLabel(value, m.status, m.bytes)
				Status.apply(value, (value.detail == "Kept" or value.detail == "Essential") and value.detail or "Within")
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
		-- A partial measurement already reads "≥" in the size column.
		row.detail = row.impact == "Safe/rebuildable" and "Rebuildable" or "Review"
		row.shareText = ""
		Status.apply(row)
		if matches(row, needle) then
			if row.impact == "Safe/rebuildable" then
				table.insert(rebuildable, row); rebuildableBytes = rebuildableBytes + row.bytes
			else
				table.insert(review, row); reviewBytes = reviewBytes + row.bytes
			end
		end
	end
	-- Each list reads largest first, like every other ranking in Diskmap; a
	-- rule's priority only orders equal sizes.
	local function bySize(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		if a.priority ~= b.priority then return a.priority < b.priority end
		return a.id < b.id
	end
	table.sort(rebuildable, bySize)
	table.sort(review, bySize)
	local elsewhere = {}
	local files = Files.summary(model)
	if files and files.reviewableOldBytes > 0 then
		table.insert(elsewhere, {id = "old-files", name = "Documents unused for a year", page = "files", filter = Files.filterIndex("Unused for a year"),
			subtitle = Model.count(files.reviewableOld) .. " of your own files over " .. Model.size(require("apps.diskmap.models.Inventory").summary.minimumFileBytes)
				.. " were not opened or changed in a year.",
			icon = "clock.fill", color = "systemOrange", bytes = files.reviewableOldBytes, size = Model.size(files.reviewableOldBytes), detail = "Large Files", shareText = ""})
	end
	local installers, installerBytes = 0, 0
	for _, row in ipairs(Files.rows(model, "Installers & archives")) do
		if row.trashable then installers = installers + 1; installerBytes = installerBytes + row.bytes end
	end
	if installerBytes > 0 then
		table.insert(elsewhere, {id = "installers", name = "Installers & archives", page = "files", filter = Files.filterIndex("Installers & archives"),
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
	for _, row in ipairs(elsewhere) do
		row.pageName = row.detail
		row.detail = "Opens " .. row.detail
		Status.apply(row, "Page")
		if matches(row, needle) then table.insert(visibleElsewhere, row) end
	end
	local checked, absent, known = Recommendations.checked(model, suggested, needle)
	return {rebuildable = relative(rebuildable), review = relative(review), elsewhere = relative(visibleElsewhere), checked = checked,
		rebuildableBytes = rebuildableBytes, reviewBytes = reviewBytes, absent = absent, known = known,
		summary = #rebuildable + #review == 0 and "No location has crossed its review threshold."
			or (Model.size(rebuildableBytes) .. " rebuildable · " .. Model.size(reviewBytes) .. " to review")}
end

-- Where a tip's action leads.
local TIP_LINKS = {settings = {settings = "privacy"}, system = {page = "guide"}, storage = {page = "overview"}}

-- The Clean Up page a ResourcePageController presents. `apps()` returns the
-- Applications summary once it is known.
function Recommendations.page(apps)
	return {view = "Cleanup", children = {tips = "Tips"}, present = function(model, state)
		local data = Recommendations.presentation(model, state.query, apps())
		local lists, hidden = {}, {}
		for _, id in ipairs({"rebuildable", "review", "elsewhere", "checked"}) do
			lists["list_" .. id] = data[id]
			hidden["section_" .. id] = #data[id] == 0
		end
		local tips, links = Tips.forInventory(model, state.disk), {}
		for _, tip in ipairs(tips) do links["tip_" .. tip.id] = TIP_LINKS[tip.action] end
		return {lists = lists, hidden = hidden, links = links, children = {tips = {tips = tips}}, texts = {
			summary = data.summary,
			rebuildableTileValue = Model.size(data.rebuildableBytes),
			rebuildableTileDetail = Model.plural(#data.rebuildable, "location") .. " regenerated by their owners",
			reviewTileValue = Model.size(data.reviewBytes),
			reviewTileDetail = Model.plural(#data.review, "location") .. " that may hold your work",
			checkedTileValue = tostring(data.known),
			checkedTileDetail = "Known space hogs checked · " .. data.absent .. " not on this Mac",
		}}
	end}
end

return Recommendations
