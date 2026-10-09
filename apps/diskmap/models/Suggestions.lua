local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local Status = require("apps.diskmap.helpers.Status")
local Xcode = require("apps.diskmap.helpers.Xcode")

-- Cleanup suggestions: the measured locations that crossed their review
-- threshold, ranked by what they could recover, how sure that is and how
-- much work it takes. A view of the store: nothing is stored, the rows are
-- computed from `locations` and `measurements` each time they are asked for.
--
-- The knowledge is the catalog entry itself (catalog/Definitions.lua): its
-- `threshold` says when a location is worth a suggestion, its `nature` what
-- the data is, its `remover` who clears it and its `advice` how. Clean Up
-- groups suggestions by remover: what Diskmap clears now, what an app or
-- System Settings clears, what a restart or the pending update clears, and
-- what only the reader can judge.
local Suggestions
Suggestions = Model:extend("suggestions", {source = function() return Suggestions:ranked() end})

-- A suggestion carries three separate numbers. `bytes` is the measured size
-- of the location (what there is to review); `eligibleBytes` is what the
-- suggestion could actually recover once every child is checked (nil when
-- that cannot be known); the score ranks by eligible bytes, how sure we are
-- and how much work the remover takes.
Suggestions.confidence = {High = 1, Medium = 0.6, Low = 0.3}
Suggestions.effort = {Low = 1, Medium = 1.5, High = 2.5}
-- Bytes to review with no eligibility proof count for this much of their size.
Suggestions.reviewFraction = 0.2
local SUPPORT_PLATFORMS = {devices = "iOS", ["watch-devices"] = "watchOS"}

-- The Clean Up sections, in page order, and the status each row shows.
Suggestions.sections = {"now", "app", "restart", "decisions"}
local SECTION_STATUS = {now = "Rebuildable", app = "Owner", restart = "Restart", decisions = "Review"}
local SECTION_DETAIL = {now = "Rebuildable", app = "Clear in its app", restart = "Restart", decisions = "Review"}
-- Data its owner makes again: fully recoverable once its remover acts.
local REGENERABLE = {cache = true, build = true, download = true, leftover = true}
local DISKMAP_CLEARS = {trash = true, ownerCommand = true}
local SYSTEM_CLEARS = {restart = true, update = true}

-- Which section a suggestion belongs to: what clears it decides, except
-- that the reader's own data and the content they chose are decisions
-- whoever removes them.
local CHOSEN = {personal = true, library = true}
function Suggestions.section(row)
	if SYSTEM_CLEARS[row.remover] then return "restart" end
	if DISKMAP_CLEARS[row.remover] then return "now" end
	if CHOSEN[row.nature] then return "decisions" end
	if row.remover == "owner" or row.remover == "setting" then return "app" end
	return "decisions"
end

-- {eligibleBytes | nil, confidence, reason | nil} for a measured resource.
-- A group agrees with its children: device support that holds only the newest
-- kept version offers nothing, and simulators offer only what the minimal
-- device set (published by the Simulators page) would remove. Otherwise what
-- the owner regenerates is fully eligible, surely when Diskmap clears it and
-- probably when its app, a restart or the pending update does.
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
	if REGENERABLE[row.nature] and DISKMAP_CLEARS[row.remover] then return measurement.bytes, "High" end
	if REGENERABLE[row.nature] or SYSTEM_CLEARS[row.remover] then return measurement.bytes, "Medium" end
	return nil, "Low"
end

-- How much work the remover asks of the reader.
local EFFORT = {trash = "Low", ownerCommand = "Low", restart = "Low", owner = "Medium", setting = "Medium", update = "Medium", finder = "High"}
local function effortOf(row)
	if DISKMAP_CLEARS[row.remover] then return "Low" end
	if row.page then return "Medium" end
	return EFFORT[row.remover] or "High"
end

function Suggestions.score(value)
	local base = value.eligibleBytes or (value.bytes * Suggestions.reviewFraction)
	return base * Suggestions.confidence[value.confidence] / Suggestions.effort[value.effort]
end
local function measured(m)
	return m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0
end
local function byScore(a, b)
	if a.score ~= b.score then return a.score > b.score end
	if a.bytes ~= b.bytes then return a.bytes > b.bytes end
	return a.id < b.id
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
		if parent and parent.id:match("^build%-") and not row:isKept() and measured(m) then
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
function Suggestions:ranked()
	local model = Model.db
	local result = {}
	Suggestions.ineligible = {}
	for _, group in ipairs(buildGroups(model)) do
		local row = group.row
		if group.bytes >= Suggestions.buildGroupThreshold and not row:isKept() then
			local proven = group.rebuildable and not group.partial
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, group = true, projects = group.count,
				bytes = group.bytes, nature = "build", remover = proven and "trash" or "finder",
				policy = group.rebuildable and "Rebuildable" or "Review"}
			Format.sizeLabel(value, group.partial and "partial" or "complete", group.bytes)
			value.impact = proven and "Safe/rebuildable" or "Needs review"
			value.threshold = Suggestions.buildGroupThreshold
			value.eligibleBytes, value.confidence, value.effort = proven and group.bytes or nil, group.rebuildable and "High" or "Low", "Low"
			value.section = Suggestions.section(value)
			value.subtitle = (row.subtitle or "") .. " In " .. Format.plural(group.count, "project") .. "."
			value.evidence = "Measured " .. value.size .. " in " .. Format.plural(group.count, "project")
			table.insert(result, value)
		end
	end
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id]
		if row.artifact then m = nil end
		if row.threshold and row.remover ~= "none" and measured(m) and m.bytes >= row.threshold
			and not row:isKept() and row.policy ~= "Essential" then
			local value = {id = row.id, name = row.name, path = row.path, policy = row.policy, action = row.action,
				nature = row.nature, remover = row.remover, page = row.page,
				subtitle = row.advice or row.subtitle, icon = row.icon, color = row.color, appIcon = row.appIcon}
			value.bytes = m.bytes
			Format.sizeLabel(value, m.status, m.bytes)
			value.impact = row.policy == "Rebuildable" and not value.partial and "Safe/rebuildable" or "Needs review"
			value.threshold = row.threshold
			value.evidence = "Measured " .. value.size .. " · Review threshold " .. Format.size(row.threshold)
			local eligible, confidence, reason = Suggestions:eligibility(row, m)
			value.eligibleBytes, value.confidence, value.effort = eligible, confidence, effortOf(row)
			value.section = value.partial and value.remover == "trash" and "decisions" or Suggestions.section(value)
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
	table.sort(result, byScore)
	return result
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

-- Every location the knowledge base has an opinion about: the catalog
-- entries with a threshold. Measured ones below their threshold, kept ones
-- and ones absent from this Mac are reported as checked, so the page shows
-- the whole checklist and not only what crossed a line.
function Suggestions:checked(suggested)
	local model = Model.db
	local rows, absent, total = {}, 0, 0
	for _, row in ipairs(Locations:leaves()) do
		local threshold = row.threshold
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
					subtitle = row.advice or row.subtitle,
					detail = row:isKept() and "Kept" or row.policy == "Essential" and "Essential" or ("Under " .. Format.size(threshold)),
					shareText = ""}
				Format.sizeLabel(value, m.status, m.bytes)
				Status.apply(value, (value.detail == "Kept" or value.detail == "Essential") and value.detail or "Within")
				table.insert(rows, value)
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
	row.section = "decisions"
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
-- rule (eligible bytes × confidence ÷ effort) and split by who clears them:
-- `now` is what Diskmap moves to the Trash or asks an owner command to
-- clear, `app` what the owning app or System Settings clears, `restart`
-- what a restart or the pending update clears, `decisions` the reader's own
-- files, apps and devices; `context` is system-managed storage that offers
-- no cleanup. `sources` carries what other pages measured: `apps` is the
-- Applications summary once it is known.
function Suggestions:presentation(sources)
	local model = Model.db
	sources = sources or {}
	local apps = sources.apps
	local lists, suggested = {}, {}
	for _, section in ipairs(Suggestions.sections) do lists[section] = {} end
	local plan = model.simulatorPlan
	for _, row in ipairs(Suggestions:ranked()) do
		suggested[row.id] = true
		-- A partial measurement already reads "≥" in the size column.
		row.detail = SECTION_DETAIL[row.section]
		row.shareText = ""
		if row.id == "simulators" and plan and plan.removalCount > 0 then
			row.subtitle = "Shared runtimes stay. "
				.. Format.size(row.bytes) .. " is stored in all simulators."
			row.decisionTitle = "Keep one iPhone and one iPad; review " .. Format.plural(plan.removalCount, "extra simulator")
			row.page, row.pageName, row.detail = "simulators", "Simulators", "Opens Simulators"
		end
		Status.apply(row, SECTION_STATUS[row.section])
		table.insert(lists[row.section], row)
	end
	local files = Files:summary()
	local elsewhere = {}
	if files and files.reviewableOldBytes > 0 then
		table.insert(elsewhere, candidate({id = "old-files", name = "Documents unused for a year", page = "files",
			subtitle = Format.count(files.reviewableOld) .. " of your own files over " .. Format.size(require("apps.diskmap.models.Scans").fileSummary.minimumFileBytes)
				.. " were not opened or changed in a year. Review them; they may be your only copy.",
			icon = "clock.fill", color = "systemOrange", bytes = files.reviewableOldBytes, detail = "Large Files"},
			{confidence = "Low", effort = "High"}))
	end
	-- Installers are the user-owned ones only: file-kind totals also count
	-- system and runtime images that this list never offers to remove.
	local installers, installerBytes = 0, 0
	for _, row in ipairs(Files:installers()) do
		installers = installers + 1; installerBytes = installerBytes + row.bytes
	end
	if installerBytes > 0 then
		table.insert(elsewhere, candidate({id = "installers", name = "Installers & archives", page = "files",
			subtitle = installers .. " disk images, installers and archives in your folders. Once installed or expanded they are rarely needed.",
			icon = "opticaldiscdrive.fill", color = "systemTeal", bytes = installerBytes, detail = "Large Files"},
			{eligibleBytes = installerBytes, confidence = "Medium", effort = "Low"}))
	end
	local worktrees = model.worktreePlan
	if worktrees and (worktrees.removalCount > 0 or worktrees.reviewCount > 0) then
		local parts = {}
		if worktrees.removalCount > 0 then table.insert(parts, Format.plural(worktrees.removalCount, "clean, published worktree") .. " can be removed") end
		if worktrees.reviewCount > 0 then table.insert(parts, Format.plural(worktrees.reviewCount, "worktree") .. " with changes or unpublished work to review") end
		table.insert(elsewhere, candidate({id = "worktrees", name = "Leftover Git worktrees", page = "worktrees",
			subtitle = table.concat(parts, "; ") .. ". Source, generated output and Git storage are counted once.",
			icon = "arrow.triangle.branch", color = "systemPurple", bytes = worktrees.removalBytes + worktrees.reviewBytes, detail = "Worktrees"},
			{eligibleBytes = worktrees.removalBytes > 0 and worktrees.removalBytes or nil, confidence = "Medium", effort = "Medium"}))
	end
	if apps and apps.leftovers and apps.leftovers > 0 then
		table.insert(elsewhere, candidate({id = "leftovers", name = "Possible app leftovers", page = "applications",
			subtitle = apps.leftovers .. " data folders belong to no installed app; " .. apps.leftoversHigh .. " are high confidence.",
			icon = "questionmark.folder.fill", color = "systemGray", bytes = apps.leftoverBytes, detail = "Applications"},
			{eligibleBytes = apps.leftoversHighBytes > 0 and apps.leftoversHighBytes or nil, confidence = apps.leftoversHighBytes > 0 and "Medium" or "Low",
				effort = "Medium"}))
	end
	if apps and apps.unused and apps.unused > 0 then
		table.insert(elsewhere, candidate({id = "unused-apps", name = "Apps unused for 6 months", page = "applications",
			subtitle = Format.plural(apps.unused, "app") .. " with a known last-use date over six months ago, and their data. Apps with an unknown last use are not counted.",
			icon = "hourglass", color = "systemBlue", bytes = apps.unusedBytes, detail = "Applications"},
			{confidence = "Low", effort = "Medium"}))
	end
	for _, row in ipairs(elsewhere) do
		row.pageName = row.detail
		row.detail = "Opens " .. row.detail
		Status.apply(row, "Page")
		table.insert(lists.decisions, row)
	end
	local eligibleBytes, reviewBytes, count, lead = 0, 0, 0, nil
	for _, section in ipairs(Suggestions.sections) do
		local rows = lists[section]
		table.sort(rows, byScore)
		for _, row in ipairs(rows) do
			count = count + 1
			eligibleBytes = eligibleBytes + (row.eligibleBytes or 0)
			-- Decisions are whole-location sizes to review, whatever part a
			-- check already proved recoverable (helpers/Scope.lua says so).
			if section == "decisions" then reviewBytes = reviewBytes + row.bytes end
			Suggestions.amount(row)
		end
		-- The first decision on the page: the highest-ranked suggestion of any section.
		local first = rows[1]
		if first and (not lead or first.score > lead.score) then lead = first end
		relative(rows)
	end
	local checked, absent, known = Suggestions:checked(suggested)
	lists.context = relative(Suggestions:context())
	lists.checked, lists.lead, lists.count = checked, lead, count
	lists.reviewBytes, lists.eligibleBytes, lists.absent, lists.known = reviewBytes, eligibleBytes, absent, known
	lists.summary = count == 0 and "No location has crossed its review threshold."
		or (Format.size(eligibleBytes) .. " estimated recoverable · " .. Format.size(reviewBytes) .. " in locations to review")
	return lists
end

-- System-managed locations: what they hold and where macOS manages them.
-- Context only; Diskmap offers no removal here.
function Suggestions:context()
	local model = Model.db
	local rows = {}
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id] or {}
		if row.nature == "system" and row.remover == "none" and measured(m) and m.bytes >= Suggestions.contextMinimum then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
				bytes = m.bytes, subtitle = row.advice or row.subtitle, detail = "System managed", shareText = ""}
			Format.sizeLabel(value, m.status, m.bytes)
			Status.apply(value, "System managed")
			table.insert(rows, value)
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
	local data = Suggestions:presentation(sources or {})
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
