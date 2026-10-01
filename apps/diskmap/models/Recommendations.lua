local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Files = require("apps.diskmap.models.Files")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Status = require("apps.diskmap.models.Status")
local Tips = require("apps.diskmap.models.Tips")
local Destinations = require("apps.diskmap.models.Destinations")
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

-- Every candidate carries the same accounting, whichever screen it comes
-- from: `bytes` is what there is to review, `eligibleBytes` what could be
-- recovered (nil when unknown), plus confidence and effort for ranking.
local function candidate(row, fields)
	for key, value in pairs(fields) do row[key] = value end
	row.shareText = row.shareText or ""
	row.size = row.size or Model.size(row.bytes)
	row.score = Cleanup.score(row)
	return row
end

-- The recovery line the inspector shows, and the prefix that tells a row's
-- bytes-to-review from bytes it could recover.
function Recommendations.recovery(row)
	if row.eligibleBytes then
		return "Estimated recoverable " .. Model.size(row.eligibleBytes) .. " · " .. (row.confidence or "Low") .. " confidence · "
			.. (row.effort or "High") .. " effort"
	end
	return Model.size(row.bytes) .. " to review · recoverable space is unknown until you choose what to remove"
end

-- The Clean Up page: candidates from every screen, ranked together by one
-- rule (eligible bytes × confidence ÷ effort) and split by what they ask of
-- the reader: rebuildable data its owner regenerates, decisions about the
-- reader's own files, apps and devices, and system-managed context that
-- offers no cleanup here. `sources` carries what other pages measured:
-- `apps` is the Applications summary once it is known.
function Recommendations.presentation(model, query, sources)
	local needle = (query or ""):lower()
	sources = sources or {}
	local apps = sources.apps
	local rebuildable, decisions, suggested = {}, {}, {}
	local rebuildableBytes, eligibleBytes, reviewBytes = 0, 0, 0
	local plan = model.simulatorPlan
	for _, row in ipairs(Cleanup.suggestions(model)) do
		suggested[row.id] = true
		-- A partial measurement already reads "≥" in the size column.
		row.detail = row.kind == "rebuildable" and "Rebuildable" or "Review"
		row.shareText = ""
		if row.id == "simulators" and plan and plan.removalCount > 0 then
			row.subtitle = "Keep one iPhone and one iPad: " .. Model.plural(plan.removalCount, "redundant device") .. " can go, " .. Model.size(plan.removalBytes)
				.. " of apps and data. Shared runtimes stay."
			row.page, row.pageName, row.detail = "simulators", "Simulators", "Opens Simulators"
		end
		Status.apply(row, row.kind == "rebuildable" and "Rebuildable" or "Review")
		if matches(row, needle) then
			if row.kind == "rebuildable" then
				table.insert(rebuildable, row); rebuildableBytes = rebuildableBytes + row.bytes
			else
				table.insert(decisions, row)
			end
		end
	end
	local files = Files.summary(model)
	local elsewhere = {}
	if files and files.reviewableOldBytes > 0 then
		table.insert(elsewhere, candidate({id = "old-files", name = "Documents unused for a year", page = "files", filter = Files.filterIndex("Unused for a year"),
			subtitle = Model.count(files.reviewableOld) .. " of your own files over " .. Model.size(require("apps.diskmap.models.Inventory").summary.minimumFileBytes)
				.. " were not opened or changed in a year. Review them; they may be your only copy.",
			icon = "clock.fill", color = "systemOrange", bytes = files.reviewableOldBytes, detail = "Large Files"},
			{confidence = "Low", effort = "High", kind = "decision"}))
	end
	-- Installers are the user-owned ones only: file-kind totals also count
	-- system and runtime images that this list never offers to remove.
	local installers, installerBytes = 0, 0
	for _, row in ipairs(Files.rows(model, "Installers & archives")) do
		installers = installers + 1; installerBytes = installerBytes + row.bytes
	end
	if installerBytes > 0 then
		table.insert(elsewhere, candidate({id = "installers", name = "Installers & archives", page = "files", filter = Files.filterIndex("Installers & archives"),
			subtitle = installers .. " disk images, installers and archives in your folders. Once installed or expanded they are rarely needed.",
			icon = "opticaldiscdrive.fill", color = "systemTeal", bytes = installerBytes, detail = "Large Files"},
			{eligibleBytes = installerBytes, confidence = "Medium", effort = "Low", kind = "decision"}))
	end
	if apps and apps.leftovers and apps.leftovers > 0 then
		table.insert(elsewhere, candidate({id = "leftovers", name = "Possible app leftovers", page = "applications",
			subtitle = apps.leftovers .. " data folders belong to no installed app; " .. apps.leftoversHigh .. " are high confidence.",
			icon = "questionmark.folder.fill", color = "systemGray", bytes = apps.leftoverBytes, detail = "Applications"},
			{eligibleBytes = apps.leftoversHighBytes > 0 and apps.leftoversHighBytes or nil, confidence = apps.leftoversHighBytes > 0 and "Medium" or "Low",
				effort = "Medium", kind = "decision"}))
	end
	if apps and apps.unused and apps.unused > 0 then
		table.insert(elsewhere, candidate({id = "unused-apps", name = "Apps unused for 6 months", page = "applications", filter = 2,
			subtitle = Model.plural(apps.unused, "app") .. " with a known last-use date over six months ago, and their data. Apps with an unknown last use are not counted.",
			icon = "hourglass", color = "systemBlue", bytes = apps.unusedBytes, detail = "Applications"},
			{confidence = "Low", effort = "Medium", kind = "decision"}))
	end
	for _, row in ipairs(elsewhere) do
		row.pageName = row.detail
		row.detail = "Opens " .. row.detail
		Status.apply(row, "Page")
		if matches(row, needle) then table.insert(decisions, row) end
	end
	table.sort(decisions, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	table.sort(rebuildable, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	for _, row in ipairs(decisions) do
		reviewBytes = reviewBytes + row.bytes
		eligibleBytes = eligibleBytes + (row.eligibleBytes or 0)
	end
	for _, row in ipairs(rebuildable) do eligibleBytes = eligibleBytes + (row.eligibleBytes or row.bytes) end
	local checked, absent, known = Recommendations.checked(model, suggested, needle)
	local context = Recommendations.context(model, needle)
	local empty = #rebuildable + #decisions == 0
	return {rebuildable = relative(rebuildable), decisions = relative(decisions), context = relative(context), checked = checked,
		rebuildableBytes = rebuildableBytes, reviewBytes = reviewBytes, eligibleBytes = eligibleBytes, absent = absent, known = known,
		summary = empty and "No location has crossed its review threshold."
			or (Model.size(eligibleBytes) .. " estimated recoverable · " .. Model.size(reviewBytes) .. " in locations to review")}
end

-- System-managed locations: what they hold and where macOS manages them.
-- Context only; Diskmap offers no removal here.
function Recommendations.context(model, needle)
	local rows = {}
	for _, row in ipairs(model.resources:leaves()) do
		local m = model.measurements[row.id] or {}
		if row.policy == "System managed" and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) >= Recommendations.contextMinimum then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
				bytes = m.bytes, subtitle = row.consequence or row.subtitle, detail = "System managed", shareText = ""}
			Model.sizeLabel(value, m.status, m.bytes)
			Status.apply(value, "System managed")
			if matches(value, needle) then table.insert(rows, value) end
		end
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.id < b.id end)
	return rows
end
Recommendations.contextMinimum = 1e9

-- Where a tip's action leads.
local TIP_LINKS = {settings = {settings = "privacy"}, system = {page = "guide"}, storage = {page = "overview"}}

-- Every section is always present; empty ones are hidden.
local SECTIONS = {
	{id = "rebuildable", title = "Rebuildable", detail = "Caches and build data their owners regenerate. Review, then clear."},
	{id = "decisions", title = "Your decisions", detail = "Files, apps and devices only you can judge, ranked by what they could recover. Size alone never makes data disposable."},
	{id = "context", title = "System-managed", detail = "macOS manages these; no cleanup is offered here.", collapsed = "Show system-managed storage"},
	{id = "checked", title = "Checked and within limits", detail = "Known space hogs below their review threshold, or kept. " .. "Locations absent from this Mac are not listed.", collapsed = "Show checked locations"},
}
local LAYOUT = {
	details = true,
	sections = {},
	slots = {"tips"},
}
for _, section in ipairs(SECTIONS) do
	table.insert(LAYOUT.sections, {id = "section_" .. section.id, title = section.title, detail = section.detail, collapsed = section.collapsed,
		list = {id = "list_" .. section.id, menu = "rowMenu", activate = "open", selectAction = "select", status = true}})
end

-- The Clean Up page a PageController presents. `apps()` returns the
-- Applications summary once it is known.
function Recommendations.details(model, row)
	if not row then
		return {title = "Select a suggestion to see what removing it does", detail = ""}
	end
	local destination = row.page and {page = row.page} or Destinations.resolve(model, row.id)
	local target = row.pageName or destination and destination.page
	local names = {simulators = "Simulators", projects = "Projects", xcode = "Xcode", files = "Large Files", applications = "Applications"}
	return {title = row.name, detail = row.subtitle or "", status = row.detail,
		size = row.size, evidence = row.kind and ((row.evidence and (row.evidence .. "\n") or "") .. Recommendations.recovery(row)) or row.evidence, consequence = row.consequence ~= row.subtitle and row.consequence or nil,
		actionTitle = "Open " .. (names[target] or target or "Details") .. "…"}
end

function Recommendations.page(sources)
	return {id = "cleanup", layout = LAYOUT, details = Recommendations.details, children = {tips = "Tips"}, present = function(model, state)
		local data = Recommendations.presentation(model, state.query, sources())
		local lists, hidden = {}, {}
		for _, section in ipairs(SECTIONS) do
			lists["list_" .. section.id] = data[section.id]
			hidden["section_" .. section.id] = #data[section.id] == 0
		end
		local tips, links = Tips.forInventory(model, state.disk), {}
		for _, tip in ipairs(tips) do links["tip_" .. tip.id] = TIP_LINKS[tip.action] end
		return {lists = lists, hidden = hidden, links = links, children = {tips = {tips = tips}}, texts = {
			summary = data.summary,
		}}
	end}
end

return Recommendations
