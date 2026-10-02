local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local Status = require("apps.diskmap.helpers.Status")
local Xcode = require("apps.diskmap.helpers.Xcode")
local Rules = require("apps.diskmap.knowledge.CleanupRules")

-- Cleanup suggestions: the measured locations that crossed a review
-- threshold, ranked by what they could recover, how sure that is and how
-- much work it takes. A view of the store: nothing is stored, the rows are
-- computed from `locations` and `measurements` each time they are asked for.
local Suggestions
Suggestions = Model:extend("suggestions", {source = function() return Suggestions:ranked() end})

-- A suggestion carries three separate numbers. `bytes` is the measured size
-- of the location (what there is to review); `eligibleBytes` is what the
-- suggestion could actually recover once every child is checked (nil when
-- that cannot be known); the score ranks by eligible bytes, how sure we are
-- and how much work the owner's flow takes.
Suggestions.confidence = {High = 1, Medium = 0.6, Low = 0.3}
Suggestions.effort = {Low = 1, Medium = 1.5, High = 2.5}
-- Bytes to review with no eligibility proof count for this much of their size.
Suggestions.reviewFraction = 0.2
local SUPPORT_PLATFORMS = {devices = "iOS", ["watch-devices"] = "watchOS"}

-- {eligibleBytes | nil, confidence, reason | nil} for a measured resource.
-- A group agrees with its children: device support that holds only the newest
-- kept version offers nothing, and simulators offer only what the minimal
-- device set (published by the Simulators page) would remove.
function Suggestions:eligibility(row, measurement)
	local model = Model.db
	local platform = SUPPORT_PLATFORMS[row.id]
	local children = platform and model.breakdowns[row.id]
	if children then
		local entries = {}
		for _, child in ipairs(children) do
			if child.directory then
				table.insert(entries, {platform = platform, name = child.name, path = child.name, bytes = math.floor((child.kb or 0) * 1024 + 0.5)})
			end
		end
		local older = Xcode.total(Xcode.supportRows(entries), function(item) return not item.keep end)
		return older, "Medium", older == 0 and "Only the newest version is present, and it is kept." or nil
	end
	-- A tool's worktree folder is reviewed worktree by worktree, so its total is
	-- not also a suggestion once that review exists.
	if row.page == "worktrees" and model.worktreePlan then
		return 0, "Medium", "Reviewed worktree by worktree on the Worktrees page."
	end
	if row.id == "simulators" and model.simulatorPlan then
		local plan = model.simulatorPlan
		return plan.removalBytes, "Medium", plan.removalBytes == 0 and "The minimal device set has nothing eligible to remove." or nil
	end
	if row.policy == "Rebuildable" then return measurement.bytes, "High" end
	return nil, "Low"
end

local function effortOf(row, rule)
	if rule and rule.effort then return rule.effort end
	if row.action == "trash" or row.action == "ownerCleanup" then return "Low" end
	if row.page then return "Medium" end
	return "High"
end

function Suggestions.score(value)
	local base = value.eligibleBytes or (value.bytes * Suggestions.reviewFraction)
	return base * Suggestions.confidence[value.confidence] / Suggestions.effort[value.effort]
end
-- Build folders are judged per ecosystem, not per folder: sixty 200 MB
-- node_modules folders are 12 GB that no single folder's threshold would
-- ever show. A group is one suggestion once its measured, unkept folders
-- reach this total; it is Rebuildable only when every one of them is.
Suggestions.buildGroupThreshold = 500e6
local function buildGroups(model)
	local groups, order = {}, {}
	for _, row in ipairs(Locations:leaves()) do
		local parent = row.artifact and row:parent()
		local m = model.measurements[row.id]
		if parent and parent.id:match("^build%-") and not row:isKept() and m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0 then
			local group = groups[parent.id]
			if not group then
				group = {row = parent, bytes = 0, projects = {}, count = 0, partial = false, rebuildable = true}
				groups[parent.id] = group
				table.insert(order, parent.id)
			end
			group.bytes = group.bytes + m.bytes
			group.partial = group.partial or m.status == "partial"
			group.rebuildable = group.rebuildable and row.policy == "Rebuildable"
			if not group.projects[row.project or row.path] then group.projects[row.project or row.path] = true; group.count = group.count + 1 end
		end
	end
	local result = {}
	for _, id in ipairs(order) do table.insert(result, groups[id]) end
	return result
end
Suggestions.buildGroups = buildGroups

-- Why a measured location is not a suggestion, by id; rebuilt on every call.
Suggestions.ineligible = {}
function Suggestions:ranked(rules)
	local model = Model.db
	local result = {}
	Suggestions.ineligible = {}
	for _, group in ipairs(buildGroups(model)) do
		local row = group.row
		if group.bytes >= Suggestions.buildGroupThreshold and not row:isKept() then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, group = true, projects = group.count,
				bytes = group.bytes,
				policy = group.rebuildable and "Rebuildable" or "Review"}
			Format.sizeLabel(value, group.partial and "partial" or "complete", group.bytes)
			value.impact = group.rebuildable and not group.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = 2, Suggestions.buildGroupThreshold
			value.eligibleBytes, value.confidence, value.effort = group.rebuildable and not group.partial and group.bytes or nil,
				group.rebuildable and "High" or "Low", "Low"
			value.kind = group.rebuildable and not group.partial and "rebuildable" or "decision"
			value.subtitle = (row.subtitle or "") .. " In " .. Format.plural(group.count, "project") .. "."
			value.evidence = "Measured " .. value.size .. " in " .. Format.plural(group.count, "project")
			table.insert(result, value)
		end
	end
	for _, row in ipairs(Locations:leaves()) do
		local m, rule = model.measurements[row.id], (rules or Rules)[row.id]
		if row.artifact then m = nil end
		if not rule and (row.reviewThreshold or row.agent or row.id == "opencode-downloads" or row.id == "grok-support") then
			rule = {threshold = row.reviewThreshold or 100e6, priority = 3, advice = row.consequence or row.subtitle}
		end
		if rule and m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) >= rule.threshold
			and not row:isKept() and row.policy ~= "Essential" then
			local value = {id = row.id, name = row.name, path = row.path, policy = row.policy, action = row.action,
				subtitle = row.subtitle, consequence = row.consequence, icon = row.icon, color = row.color, appIcon = row.appIcon}
			value.bytes = m.bytes
			Format.sizeLabel(value, m.status, m.bytes)
			value.impact = row.policy == "Rebuildable" and not value.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = rule.priority, rule.threshold
			value.subtitle = rule.advice
			value.evidence = "Measured " .. value.size .. " · Review threshold " .. Format.size(rule.threshold)
			local eligible, confidence, reason = Suggestions:eligibility(row, m)
			value.eligibleBytes, value.confidence, value.effort = eligible, confidence, effortOf(row, rule)
			value.kind = value.impact == "Safe/rebuildable" and "rebuildable" or "decision"
			if eligible and eligible ~= m.bytes then
				value.evidence = value.evidence .. " · " .. Format.size(eligible) .. " eligible after keeping what is current"
			end
			if reason then
				-- Nothing to do here: the page says why instead of sending the reader
				-- to a destination with no candidate.
				Suggestions.ineligible[row.id] = reason
			else
				table.insert(result, value)
			end
		end
	end
	for _, value in ipairs(result) do value.score = Suggestions.score(value) end
	table.sort(result, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	return result
end
local function matches(row, needle)
	return needle == "" or ((row.name or "") .. " " .. (row.subtitle or "") .. " " .. (row.path or "")):lower():find(needle, 1, true) ~= nil
end

local function relative(rows)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.shownBytes or row.bytes or 0) end
	for _, row in ipairs(rows) do row.relative = largest > 0 and (row.shownBytes or row.bytes or 0) / largest or 0 end
	return rows
end

-- A suggestion's prominent amount is what it could recover when a check
-- proved that, and otherwise what there is to review; the meter's caption
-- says which, so a whole-location size never reads as a recovery estimate.
function Suggestions.amount(row)
	if row.eligibleBytes and row.eligibleBytes > 0 then
		row.shownBytes = row.eligibleBytes
		if row.eligibleBytes ~= row.bytes or not row.size then row.size = Format.size(row.eligibleBytes) end
		row.shareText = "could recover"
	else
		row.shownBytes = row.bytes
		row.shareText = "to review"
	end
	return row
end

-- Every location the knowledge base has an opinion about: cleanup rules and
-- catalog review thresholds. Measured ones below their threshold, kept ones
-- and ones absent from this Mac are reported as checked, so the page shows
-- the whole checklist and not only what crossed a line.
function Suggestions:checked(suggested, needle)
	local model = Model.db
	local rows, absent, total = {}, 0, 0
	for _, row in ipairs(Locations:leaves()) do
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
					detail = row:isKept() and "Kept" or row.policy == "Essential" and "Essential" or ("Under " .. Format.size(threshold)),
					shareText = ""}
				Format.sizeLabel(value, m.status, m.bytes)
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
	row.size = row.size or Format.size(row.bytes)
	row.score = Suggestions.score(row)
	return row
end

-- The recovery line the inspector shows, and the prefix that tells a row's
-- bytes-to-review from bytes it could recover.
function Suggestions.recovery(row)
	if row.eligibleBytes then
		return "Estimated recoverable " .. Format.size(row.eligibleBytes) .. " · " .. (row.confidence or "Low") .. " confidence · "
			.. (row.effort or "High") .. " effort"
	end
	return Format.size(row.bytes) .. " to review · recoverable space is unknown until you choose what to remove"
end

-- The Clean Up page: candidates from every screen, ranked together by one
-- rule (eligible bytes × confidence ÷ effort) and split by what they ask of
-- the reader: rebuildable data its owner regenerates, decisions about the
-- reader's own files, apps and devices, and system-managed context that
-- offers no cleanup here. `sources` carries what other pages measured:
-- `apps` is the Applications summary once it is known.
function Suggestions:presentation(query, sources)
	local model = Model.db
	local needle = (query or ""):lower()
	sources = sources or {}
	local apps = sources.apps
	local rebuildable, decisions, suggested = {}, {}, {}
	local rebuildableBytes, eligibleBytes, reviewBytes = 0, 0, 0
	local plan = model.simulatorPlan
	for _, row in ipairs(Suggestions:ranked()) do
		suggested[row.id] = true
		-- A partial measurement already reads "≥" in the size column.
		row.detail = row.kind == "rebuildable" and "Rebuildable" or "Review"
		row.shareText = ""
		if row.id == "simulators" and plan and plan.removalCount > 0 then
			row.subtitle = "Shared runtimes stay. "
				.. Format.size(row.bytes) .. " is stored in all simulators."
			row.decisionTitle = "Keep one iPhone and one iPad; review " .. Format.plural(plan.removalCount, "extra simulator")
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
	local files = Files:summary()
	local elsewhere = {}
	if files and files.reviewableOldBytes > 0 then
		table.insert(elsewhere, candidate({id = "old-files", name = "Documents unused for a year", page = "files", filter = Files.filters:index("Unused for a year"),
			subtitle = Format.count(files.reviewableOld) .. " of your own files over " .. Format.size(require("apps.diskmap.models.Scans").fileSummary.minimumFileBytes)
				.. " were not opened or changed in a year. Review them; they may be your only copy.",
			icon = "clock.fill", color = "systemOrange", bytes = files.reviewableOldBytes, detail = "Large Files"},
			{confidence = "Low", effort = "High", kind = "decision"}))
	end
	-- Installers are the user-owned ones only: file-kind totals also count
	-- system and runtime images that this list never offers to remove.
	local installers, installerBytes = 0, 0
	for _, row in ipairs(Files:rows("Installers & archives")) do
		installers = installers + 1; installerBytes = installerBytes + row.bytes
	end
	if installerBytes > 0 then
		table.insert(elsewhere, candidate({id = "installers", name = "Installers & archives", page = "files", filter = Files.filters:index("Installers & archives"),
			subtitle = installers .. " disk images, installers and archives in your folders. Once installed or expanded they are rarely needed.",
			icon = "opticaldiscdrive.fill", color = "systemTeal", bytes = installerBytes, detail = "Large Files"},
			{eligibleBytes = installerBytes, confidence = "Medium", effort = "Low", kind = "decision"}))
	end
	local worktrees = model.worktreePlan
	if worktrees and (worktrees.removalCount > 0 or worktrees.reviewCount > 0) then
		local parts = {}
		if worktrees.removalCount > 0 then table.insert(parts, Format.plural(worktrees.removalCount, "clean, published worktree") .. " can be removed") end
		if worktrees.reviewCount > 0 then table.insert(parts, Format.plural(worktrees.reviewCount, "worktree") .. " with changes or unpublished work to review") end
		table.insert(elsewhere, candidate({id = "worktrees", name = "Leftover Git worktrees", page = "worktrees",
			subtitle = table.concat(parts, "; ") .. ". Source, generated output and Git storage are counted once.",
			icon = "arrow.triangle.branch", color = "systemPurple", bytes = worktrees.removalBytes + worktrees.reviewBytes, detail = "Worktrees"},
			{eligibleBytes = worktrees.removalBytes > 0 and worktrees.removalBytes or nil, confidence = "Medium", effort = "Medium", kind = "decision"}))
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
			subtitle = Format.plural(apps.unused, "app") .. " with a known last-use date over six months ago, and their data. Apps with an unknown last use are not counted.",
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
	for _, row in ipairs(rebuildable) do Suggestions.amount(row) end
	for _, row in ipairs(decisions) do Suggestions.amount(row) end
	-- The first decision on the page: the highest-ranked suggestion of either kind.
	local lead
	for _, row in pairs({rebuildable = rebuildable[1], decisions = decisions[1]}) do
		if not lead or row.score > lead.score or (row.score == lead.score and row.kind == "rebuildable") then lead = row end
	end
	local checked, absent, known = Suggestions:checked(suggested, needle)
	local context = Suggestions:context(needle)
	local empty = #rebuildable + #decisions == 0
	return {rebuildable = relative(rebuildable), decisions = relative(decisions), context = relative(context), checked = checked, lead = lead,
		count = #rebuildable + #decisions,
		rebuildableBytes = rebuildableBytes, reviewBytes = reviewBytes, eligibleBytes = eligibleBytes, absent = absent, known = known,
		summary = empty and "No location has crossed its review threshold."
			or (Format.size(eligibleBytes) .. " estimated recoverable · " .. Format.size(reviewBytes) .. " in locations to review")}
end

-- System-managed locations: what they hold and where macOS manages them.
-- Context only; Diskmap offers no removal here.
function Suggestions:context(needle)
	local model = Model.db
	local rows = {}
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id] or {}
		if row.policy == "System managed" and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) >= Suggestions.contextMinimum then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
				bytes = m.bytes, subtitle = row.consequence or row.subtitle, detail = "System managed", shareText = ""}
			Format.sizeLabel(value, m.status, m.bytes)
			Status.apply(value, "System managed")
			if matches(value, needle) then table.insert(rows, value) end
		end
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.id < b.id end)
	return rows
end
Suggestions.contextMinimum = 1e9

-- Headline for the Clean Up call to action: the same estimate Clean Up and
-- its sidebar badge state, computed by the same presentation, so the three
-- never name different numbers. What could be recovered leads; bytes that
-- only a person can judge follow as bytes to review, never added to it.
-- `sources` is what other pages measured (the Applications summary).
function Suggestions:reclaim(sources)
	local data = require("apps.diskmap.models.Suggestions"):presentation("", sources or {})
	local result = {count = data.count, eligible = data.eligibleBytes, review = data.reviewBytes, top = data.lead and data.lead.name or nil}
	if data.count == 0 then
		result.title = "No cleanup suggestions yet"
		result.detail = "Suggestions appear once measured caches or build data exceed their review thresholds."
	elseif data.eligibleBytes > 0 then
		result.title = Format.size(data.eligibleBytes) .. " could recover"
		result.detail = data.count .. (data.count == 1 and " suggestion" or " suggestions")
			.. (data.reviewBytes > 0 and (" · " .. Format.size(data.reviewBytes) .. " more to review") or "")
			.. (result.top and (" · start with " .. result.top) or "")
	else
		-- Nothing is proven recoverable yet; lead with what can be reviewed
		-- rather than a zero.
		result.title = Format.size(data.reviewBytes) .. " to review"
		result.detail = data.count .. (data.count == 1 and " suggestion" or " suggestions") .. " · nothing recoverable without review"
	end
	return result
end

return Suggestions
