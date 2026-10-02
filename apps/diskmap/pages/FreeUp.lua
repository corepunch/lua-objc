local Model = require("data.model")
local Provider = require("apps.diskmap.services.Provider")
local Applications = require("apps.diskmap.models.Applications")
local Duplicates = require("apps.diskmap.helpers.Duplicates")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local Inventory = require("apps.diskmap.helpers.Inventory")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Projects = require("apps.diskmap.models.Projects")
local Scope = require("apps.diskmap.helpers.Scope")

-- The pages that free up space: Applications, Large Files, Duplicates and
-- Projects (Simulators and Worktrees are pages/Simulators.lua and
-- pages/Worktrees.lua). Each list route's constants stay in its own block.
local routes = {}

do
	-- Decisions first: data left behind by apps that are gone, then the
	-- installed apps as the inventory that explains them.
	local LAYOUT = {
		summary = "Reading installed applications…",
		leads = {"lead"},
		sections = {
			{id = "leftoversSection", title = "Possible leftovers",
				detail = "Data folders no app on this Mac claims. High means no app from that vendor is installed; review Medium and Low before removing anything. Reinstalling the app starts it fresh.",
				list = {id = "leftovers", menu = "rowMenu", activate = "reveal", detailColumn = true}},
			{title = "Installed", detailId = "installedDetail", detail = "Each app with the data it keeps in your Library.",
				filters = {id = "filter", options = Applications.filters},
				list = {id = "apps", menu = "rowMenu", activate = "reveal", detailColumn = true}},
		},
		footnote = {text = "Last used comes from Spotlight, as Finder's Last Opened; an app without a recorded date reads Last use unknown and is never counted as unused. Apps outside /Applications and ~/Applications are not listed; their data never counts as a leftover."},
	}

	local WAITING = {title = "Applications Not Measured Yet", systemImage = "square.grid.3x3", description = "Apps and the data they keep are listed when the scan finishes."}
	local LINKS = {cleanup = {page = "cleanup"}, reviewMarked = {handler = "review"}}

	-- `leftover` lets the cleanup skip it if its app is installed again.
	local function leftoverItem(row)
		return {path = row.path, name = row.name, bytes = row.bytes, source = "Leftovers · " .. row.source, leftover = true,
			consequence = "Settings, caches and documents of an app that is no longer installed. Reinstalling the app starts it fresh. Confidence: "
				.. row.confidence .. " (" .. row.reason .. ")."}
	end

	local function trashLeftover(page, row)
		local service = page.app.service
		local ok, reason = Applications:validateLeftover(row.path)
		if not ok then service.showError("Cannot move to Trash", reason.message); return end
		if not service.confirmTrashPath("Move " .. row.name .. " to Trash?", row.path,
			row.size .. ". No installed app uses this identifier, but an app on another disk or reinstalled later would lose these settings and data. Moving to Trash does not free space until you empty it.") then return end
		local moved, message = service.trash(row.path)
		if not moved then service.showError("Could not move to Trash", message or "macOS protects some containers. Remove it in Finder instead."); return end
		page.app.rescan()
	end

	-- The Applications page and the app facts other pages need. Bundle info and
	-- the installed-identifier list load in the background once per set of
	-- discovered bundles, and the page is drawn again when they arrive.
	routes.applications = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision"}, load = function(page)
			page:loadFacts()
			if (page.pending or 0) > 0 then page.app.refresh() end
		end,
		menu = function(page, row)
			if not row.tier then return page.actions:application(row) end
			return page.actions:folder(row, function(value) trashLeftover(page, value) end, leftoverItem(row))
		end,
		actions = {
			-- File Types and Clean Up open the page on one filter.
			focus = function(page, filterIndex) page.filterIndex = filterIndex or 1 end,
			unusedFilter = function(page) page.filterIndex = 2 end,
			markHigh = function(page)
				local items = {}
				for _, row in ipairs(page.visibleLeftovers or {}) do
					if row.tier == "high" then table.insert(items, leftoverItem(row)) end
				end
				page.actions:markAll(items)
			end,
			-- Loads bundle info for the currently discovered apps, once per bundle
			-- set, and the installed identifiers once per session.
			loadFacts = function(page)
				local service, paths = page.app.service, {}
				for _, bundle in ipairs(Applications:all()) do table.insert(paths, bundle.path) end
				table.sort(paths)
				local key = table.concat(paths, "\n")
				if key ~= page.loadedKey and Provider.offers(service, "applicationInfo") then
					page.loadedKey, page.pending = key, (page.pending or 0) + 1
					service.applicationInfo(paths, function(info)
						page.pending = page.pending - 1
						if page.loadedKey == key then Model.db.applicationInfo = info; page.app.refresh() end
					end)
				end
				if not page.installedRequested and Provider.offers(service, "installedBundleIds") then
					page.installedRequested, page.pending = true, (page.pending or 0) + 1
					service.installedBundleIds(function(ids) page.pending = page.pending - 1; Model.db.installedBundleIds = ids; page.app.refresh() end)
				end
			end,
			-- Summary for the Clean Up page; nil until the scan has measured data folders.
			summary = function(page)
				local model = Model.db
				if not model.files or model.files.measuring then return nil end
				return Applications.summary(Applications:rows("All"), Applications:leftovers())
			end,
		}, present = function(page, state)
			local model = Model.db
			-- Nothing is listed until the scan has measured the apps and Spotlight has told their facts.
			page.visibleLeftovers = {}
			if model.scan.running then return {waiting = WAITING} end
			if (page.pending or 0) > 0 then return {computing = "Reading installed applications…"} end
			local leftovers = Applications:leftovers(state.query)
			page.visibleLeftovers = leftovers or {}
			local unmarkedHigh, markedHigh = 0, 0
			for _, row in ipairs(leftovers or {}) do
				if row.tier == "high" then
					if page.actions:isIncluded(row.path) then markedHigh = markedHigh + 1 else unmarkedHigh = unmarkedHigh + 1 end
				end
			end
			local summary = Applications.summary(Applications:rows("All"), Applications:leftovers())
			return {lists = {apps = Applications:rows(Applications.filters[page.filterIndex], state.query),
				leftovers = page.actions:annotate(leftovers or {})}, links = LINKS,
				hidden = {leftoversSection = not leftovers or #leftovers == 0},
				children = {lead = Applications.decision(summary, unmarkedHigh, markedHigh, Model.db.applicationInfo ~= nil)}, texts = {
				summary = summary.count == 0 and "No applications measured yet."
					or string.format("%s %s %s, and their data another %s stored.", Format.plural(summary.count, "app"), summary.count == 1 and "uses" or "use", Format.size(summary.apps), Format.size(summary.data)),
				installedDetail = "Each app with the data it keeps in your Library."
					.. (Model.db.applicationInfo and summary.unused > 0 and (" " .. Format.plural(summary.unused, "app") .. " with a known last use over six months ago, " .. Format.size(summary.unusedBytes) .. " with " .. (summary.unused == 1 and "its" or "their") .. " data.") or "")}}
		end})
end

do
	local THRESHOLD = Format.size(Inventory.summary.minimumFileBytes)
	local LAYOUT = {
		summary = "Measuring files…", scopeNote = Scope.pages.files, leads = {"lead"}, contextAfterSections = true, contextDisclosure = "Scan scope and statistics",
		tiles = {
			{id = "largeTile", icon = "doc.fill", color = "systemTeal", title = "Over " .. THRESHOLD, value = "—", detail = "Individual files, largest first"},
			{id = "oldTile", icon = "clock.fill", color = "systemOrange", title = "Unused for a year", value = "—", detail = "Not opened or changed since"},
			{id = "movableTile", icon = "trash.fill", color = "systemRed", title = "Yours to review", value = "—", detail = "Unused documents you can move to the Trash"},
		},
		sections = {{
			controlsId = "fileControls",
			links = {{id = "clearKind", title = "Show All Kinds", style = "link", action = "clearKind"}},
			filters = {id = "filter", options = Files.filters},
			empties = {
				{id = "filesUnavailable", title = "File Results Unavailable", systemImage = "exclamationmark.triangle", description = "Check scan access, then refresh to measure files again."},
				{id = "filesNone", title = "No Large Files Found", systemImage = "doc", description = "No files over " .. THRESHOLD .. " were ranked. Clean Up can still find rebuildable data."},
				{id = "filesNoResults", title = "No Results", systemImage = "magnifyingglass", description = "No large file matches the search. Try another filter or search."},
				{id = "filesEmpty", title = "No Files Here", systemImage = "doc", description = "No large file fits this filter. Choose All to see every file Diskmap ranked."},
			},
			panelId = "filesPanel",
			list = {id = "files", menu = "rowMenu", activate = "reveal", detailColumn = true, fileIcons = true}}},
		footnote = {text = "Diskmap reads only names, sizes and dates. Files inside apps, libraries and hidden tool folders are listed for context and managed by their owners; only your own documents can be moved to the Trash here."},
	}

	local WAITING = {title = "Files Not Measured Yet", systemImage = "doc", description = "Large files are listed when the scan finishes."}
	local LINKS = {cleanup = {page = "cleanup"}, reviewMarked = {handler = "review"}, refreshFiles = {handler = "refresh"},
		clearSearch = {handler = "search", args = {"files", ""}}}

	-- The lead card: what a person can mark here, or why there is nothing to.
	local function decision(page, rows, fileState, reason, query, kind, noFiles)
		local filter, actions = Files.filters[page.filterIndex], page.actions
		local bytes, reviewable, marked, included = 0, 0, 0, 0
		for _, row in ipairs(rows) do
			bytes = bytes + row.bytes
			if Files:validateTrash(row.path) then
				if actions:isMarked(row.path) then marked = marked + 1
				elseif actions:isIncluded(row.path) then marked, included = marked + 1, included + 1
				else reviewable = reviewable + 1 end
			end
		end
		local data = {id = "decision", icon = "doc.fill", color = "systemTeal",
			title = (kind and kind.name or filter) .. " · " .. Format.plural(#rows, "file"),
			detail = filter == "Installers & archives" and "Check that these are installed or extracted. Marking stages them for your final review."
				or "Review the contents before marking. Files inside apps or libraries stay with their owners.",
			amount = Format.size(bytes), amountCaption = "to review",
			actionTitle = reviewable > 0 and ("Mark " .. Format.plural(reviewable, "File")) or (marked > 0 and "Review Marked Items…" or "No Files to Mark"),
			action = reviewable > 0 and "markFiles" or "reviewMarked", disabled = reviewable == 0 and marked == 0,
			secondaryTitle = reviewable > 0 and marked > 0 and "Review Marked Items…" or nil, secondaryAction = "reviewMarked"}
		if included > 0 then data.detail = Format.plural(included, "file") .. " included through a marked folder. Review the folder to change its cleanup plan." end
		local function say(title, detail, caption, actionTitle, action)
			data.title, data.detail, data.amount, data.amountCaption = title, detail, "—", caption
			data.actionTitle, data.action, data.disabled = actionTitle, action, false
		end
		if noFiles then
			say("No large files found", "No files over " .. THRESHOLD .. " were ranked. Review rebuildable data in Clean Up.", "scan finished", "Open Clean Up", "cleanup")
		elseif fileState == "error" or fileState == "unavailable" then
			say("File results unavailable", reason, "not measured", "Refresh Scan", "refreshFiles")
		elseif #rows == 0 and query ~= "" then
			say("Nothing matches this search", "Clear the search or choose another filter to review the measured files.", "no matches", "Clear Search", "clearSearch")
		end
		return data
	end

	-- Large Files: the individual files the last scan ranked, with filters for
	-- files unused for a year, installers and media. File Types opens it on one
	-- kind (`focus`).
	routes.files = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision"}, menu = function(page, row) return page.actions:file(row) end,
		actions = {
			-- Opens the page narrowed to one File Types kind and one filter.
			focus = function(page, kind, filterIndex) page.kind, page.filterIndex = kind, filterIndex or 1 end,
			clearKind = function(page) page.kind = nil end,
			-- Mark only the visible, user-owned subset. This stages the files; the
			-- existing basket supplies the review and confirmation before removal.
			markFiles = function(page)
				local items = {}
				for _, row in ipairs(page.visible or {}) do
					if Files:validateTrash(row.path) and not page.actions:isIncluded(row.path) then
						table.insert(items, {path = row.path, name = row.name, bytes = row.bytes,
							source = "Large Files", consequence = "Moved to the Trash after your final review. Check that this is not your only copy."})
					end
				end
				return page.actions:markAll(items)
			end,
		}, present = function(page, state)
			local model = Model.db
			-- Nothing is listed until the scan has measured the files.
			local fileState, reason = Files:state()
			page.visible = {}
			if fileState == "loading" then return {waiting = WAITING} end
			local query, kind = state.query or "", page.kind and Files.kindById(page.kind)
			local files, summary = model.files, Files:summary()
			local rows = Files:rows(Files.filters[page.filterIndex], query, page.kind)
			page.visible = rows
			local noLarge = files ~= nil and #files.large == 0 and #files.old == 0
			local noFiles = fileState == "empty" or (fileState == "loaded" and noLarge)
			local unavailable = fileState == "error" or fileState == "unavailable"
			local listed = files ~= nil and #rows == 0 and fileState == "loaded" and not noLarge
			local texts = {scopeNote = Scope.text("files"), summary = not summary and "No file results are available. Refresh to try again."
				or "Files over " .. THRESHOLD .. " · " .. (summary.partial and "scan coverage is incomplete" or "largest first")}
			if summary then
				texts.largeTileValue, texts.largeTileDetail = Format.size(summary.bytes), Format.plural(Format.count(summary.count), "file") .. ", largest first"
				texts.oldTileValue, texts.oldTileDetail = Format.size(summary.oldBytes), Format.plural(Format.count(summary.oldCount), "file") .. " not opened or changed in a year"
				texts.movableTileValue = Format.size(summary.reviewableOldBytes)
				texts.movableTileDetail = Format.plural(Format.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"
			end
			return {lists = {files = page.actions:annotate(rows)}, texts = texts, links = LINKS,
				children = {lead = decision(page, rows, fileState, reason, query, kind, noFiles)}, hidden = {
					filesPanel = #rows == 0 or unavailable, fileControls = unavailable or noLarge,
					filesUnavailable = not unavailable, filesNone = not noFiles,
					filesEmpty = not (listed and query == ""), filesNoResults = not (listed and query ~= ""), clearKind = kind == nil}}
		end})
end

do
	-- The Duplicates page. Reading contents is a privacy boundary, so nothing is
	-- read until the person adds a folder and starts a search, and only that
	-- folder is read. Results last for the session. While a search runs the page
	-- is computing; otherwise exactly one of these notes shows, by
	-- `Duplicates.state`, so "nothing chosen yet" is never read as "nothing found".
	local EMPTIES = {
		{state = "choose", id = "dupChoose", title = "Choose Folders to Scan", systemImage = "folder.badge.plus",
			description = "Add a folder such as Downloads or Documents. Files are compared byte for byte; nothing is read outside the folders you add."},
		{state = "ready", id = "dupReady", title = "Ready to Search", systemImage = "doc.on.doc",
			description = "Choose Find Duplicates to compare the files in the folders above. Nothing has been read yet."},
		{state = "none", id = "dupNone", title = "No Duplicates Found", systemImage = "checkmark.circle",
			description = "The search finished: no two files in the chosen folders are identical. Files under 1 MB are not compared."},
		{state = "nomatch", id = "dupNoMatch", title = "No Match", systemImage = "magnifyingglass",
			description = "No group of duplicates matches the search. Clear the search to see them all."},
		{state = "failed", id = "dupFailed", title = "The Search Did Not Finish", systemImage = "exclamationmark.triangle",
			description = "Diskmap could not read these folders. Check that it may access them, then choose Find Duplicates again."},
	}

	local LAYOUT = {
		summary = "Identical files in folders you choose.",
		buttons = {{id = "addFolder", title = "Add Folder…", systemImage = "plus", action = "addFolder"},
			{id = "search", title = "Find Duplicates", action = "search"}},
		sections = {{title = "Identical files", detailId = "duplicateRoots", empties = EMPTIES, panelId = "duplicatesList",
			list = {id = "duplicates", menu = "rowMenu", activate = "reveal", detailColumn = true}}},
		footnote = {text = "Copies that are APFS clones share their storage with the original: removing one frees only what it does not share, which is what Can free shows."},
	}

	local function service(page) return page.app.service end

	local function search(page)
		if #page.roots == 0 then return end
		page.result, page.progress = nil, {examined = 0}
		page.job = service(page).findDuplicates(page.roots, function(result)
			page.job, page.result, page.progress = nil, result, nil
			page.app.refresh()
		end, function(progress) page.progress = progress; page.app.refresh() end)
	end

	local function addFolder(page)
		local pick = Provider.offers(service(page), "pickFolder")
		local path = pick and pick("Choose a Folder to Compare")
		if not path then return end
		for _, root in ipairs(page.roots) do if root == path then return end end
		table.insert(page.roots, path)
		local save = Provider.offers(service(page), "saveFolders")
		if save then save("duplicates", page.roots) end
		page.result = nil
	end

	-- What a row offers: mark every copy but the kept one, or review the marks
	-- when a marked folder already covers them; reveal each file.
	local function menu(page, row)
		local items, keep = Duplicates.copies(row.group)
		local available, enclosing = {}, nil
		for _, item in ipairs(items) do
			local parent = page.actions:covering(item.path)
			if parent then enclosing = enclosing or parent.path else table.insert(available, item) end
		end
		local marking = #available > 0
		local reveal = service(page).reveal
		local menu = {{title = marking and ("Mark " .. #available .. (#available == 1 and " Copy" or " Copies") .. " for Cleanup") or "Review Marked Items…",
			systemImage = marking and "plus.circle" or "checkmark.circle",
			action = function() if marking then page.actions:markAll(available) else page.page.app.openReview(enclosing) end end}}
		table.insert(menu, {title = "Show Kept Copy", systemImage = "folder", action = function() reveal(keep.path) end})
		for _, item in ipairs(items) do
			table.insert(menu, {title = "Show " .. Format.tilde(item.path, Model.db.home), systemImage = "doc", action = function() reveal(item.path) end})
		end
		return menu
	end

	local function summaryText(page, groups)
		local result = page.result
		if result and (result.failure or result.groups == nil) then return "The search did not finish." end
		if not result then return #page.roots == 0 and LAYOUT.summary or "Ready to compare the chosen folders." end
		local summary = Duplicates.summary(groups)
		if summary.groups == 0 then return "No identical files found." end
		return string.format("%d %s could free %s", summary.copies, summary.copies == 1 and "copy" or "copies", Format.size(summary.bytes))
	end

	routes.duplicates = ListRoute.extend({layout = LAYOUT, actions = {
			addFolder = addFolder,
			search = function(page) if page.job then page.job.cancel(); page.job, page.progress = nil, nil else search(page) end end,
		}, menu = menu, present = function(page, state)
			local storage = Model.db
			if not page.roots then
				local load = Provider.offers(service(page), "loadFolders")
				page.roots = load and load("duplicates") or {}
			end
			local presented = {texts = {search = page.job and "Stop" or "Find Duplicates"}, disabled = {addFolder = page.job ~= nil, search = #page.roots == 0}}
			if page.job then
				presented.computing = string.format("Comparing… %s files examined", Format.count(page.progress and page.progress.examined or 0))
				return presented
			end
			local result = page.result
			local groups = result and not result.failure and result.groups or {}
			local rows = page.actions:annotate(Duplicates.rows(groups, state.query, storage.home))
			local current = Duplicates.state(page.roots, result, #rows, state.query)
			local names = {}
			for _, root in ipairs(page.roots) do table.insert(names, Format.tilde(root, storage.home)) end
			local hidden = {duplicatesList = current ~= "list"}
			for _, empty in ipairs(EMPTIES) do hidden[empty.id] = current ~= empty.state end
			presented.lists, presented.hidden = {duplicates = rows}, hidden
			presented.texts.summary = summaryText(page, groups)
			presented.texts.duplicateRoots = #names == 0 and "Add the folders to compare. Diskmap reads file contents only in them."
				or "Comparing files in " .. table.concat(names, ", ") .. "."
			return presented
		end})
end

do
	local LAYOUT = {
		summary = "Build data your projects can recreate.", summaryId = "projectsSummary",
		buttons = {{id = "addFolder", title = "Add Folder…", systemImage = "plus", action = "addFolder", help = "Search another folder for projects"}},
		sections = {{title = "Build folders", detailId = "projectRoots",
			filters = {id = "filter", options = Projects.filters},
			buttons = {{id = "markStale", title = "Mark Old Build Data", systemImage = "plus.circle", action = "markStale",
				help = "Mark build data of projects with a clean git tree, untouched for three months"}},
			empties = {{id = "projectsEmpty", title = "No Build Folders Found", systemImage = "folder.badge.gearshape",
				description = "Projects appear here once Diskmap finds node_modules, target, .build and similar folders beside their project files."}},
			panelId = "projectsList",
			list = {id = "projects", menu = "rowMenu", activate = "reveal", detailColumn = true}}},
		footnote = {text = "Only folders a project's tools create (node_modules, target, .build, …) are listed. Projects with uncommitted or unpushed work are never marked in bulk."},
	}

	local WAITING = {title = "Projects Not Found Yet", systemImage = "folder.badge.gearshape", description = "Build folders are listed when the scan finishes."}

	local function groups(page, filter, query)
		return Projects:groups(filter, query)
	end

	-- A project is marked when all of its generated folders are.
	local function isMarked(page, group)
		for _, artifact in ipairs(group.artifacts) do
			if not page.actions:isMarked(artifact.path) then return false end
		end
		return #group.artifacts > 0
	end

	-- Whether every generated folder is covered by a mark, and the enclosing
	-- marked folder if one covers them from above.
	local function included(page, group)
		local enclosing
		for _, artifact in ipairs(group.artifacts) do
			local item, exact = page.actions:covering(artifact.path)
			if not item then return false end
			if not exact then enclosing = enclosing or item end
		end
		return #group.artifacts > 0, enclosing
	end

	local function mark(page, group)
		local review, marked = page.app.review, isMarked(page, group)
		for _, artifact in ipairs(group.artifacts) do
			if (marked and page.actions:isMarked(artifact.path)) or (not marked and not page.actions:covering(artifact.path)) then
				review:toggle({path = artifact.path, name = artifact.name .. " · " .. group.name, bytes = artifact.bytes,
					source = "Projects", consequence = "Generated by the project's tools and recreated by its next build or install."
						.. (group.dirty and " This project has uncommitted or unpushed work; its sources are not touched." or "")})
			end
		end
	end

	-- Old build data of a project whose git tree is clean.
	local function stale(page, query)
		local found = {}
		for _, group in ipairs(groups(page, Projects.filters[2], query)) do
			if type(group.git) == "table" and group.git.clean and not included(page, group) then table.insert(found, group) end
		end
		return found
	end

	local function rootsText(page)
		local roots = {"~/Developer"}
		for _, root in ipairs(Model.db.projectRoots or {}) do table.insert(roots, Format.tilde(root, Model.db.home)) end
		return table.concat(roots, ", ")
	end

	-- Git state and age are read one project at a time, then the page is drawn
	-- again. A visit that ended meanwhile bumps the generation.
	local function loadInfo(page)
		local service = page.app.service
		if type(service.projectInfo) ~= "function" or page.loadingInfo then return end
		local queue = {}
		for _, group in ipairs(groups(page, Projects.filters[1])) do
			if not Model.db.projectInfo[group.path] then table.insert(queue, group.path) end
		end
		if #queue == 0 then return end
		page.loadingInfo = true
		local generation = page.generation
		local function step(index)
			if generation ~= page.generation then return end
			if index > #queue then page.loadingInfo = false; page.app.refresh(); return end
			service.projectInfo(queue[index], function(info)
				Model.db.projectInfo[queue[index]] = info or {loaded = true}
				step(index + 1)
			end)
		end
		step(1)
	end

	-- The Projects page: generated build folders found beside their project
	-- markers, grouped by project with git state and age. Marking a project marks
	-- its generated folders, never its sources.
	routes.projects = ListRoute.extend({layout = LAYOUT,
		load = function(page) page.generation = (page.generation or 0) + 1; Model.db.projectInfo = Model.db.projectInfo or {}; loadInfo(page) end,
		unload = function(page) page.generation = page.generation + 1; page.loadingInfo = false end,
		-- A project's menu marks all of its build folders at once; its sources are
		-- never offered.
		menu = function(page, group)
			local actions, service = page.actions, page.app.service
			local all, enclosing = included(page, group)
			if all and enclosing then
				return {{title = "Included through Marked Folder — Review…", systemImage = "folder.badge.checkmark",
					action = function() page.app.openReview(enclosing.path) end}, actions:reveal(group.path), actions:copyPath(group.path)}
			end
			local marked = isMarked(page, group)
			local items = {{title = marked and "Unmark Build Data" or "Mark Build Data for Cleanup", systemImage = marked and "minus.circle" or "plus.circle",
				action = function() mark(page, group) end}}
			for _, artifact in ipairs(group.artifacts) do
				table.insert(items, {title = "Show " .. artifact.name .. " (" .. artifact.size .. ")", systemImage = "folder",
					action = function() service.reveal(artifact.path) end})
			end
			table.insert(items, {separator = true})
			table.insert(items, actions:reveal(group.path))
			table.insert(items, actions:copyPath(group.path))
			return items
		end,
		actions = {
			markStale = function(page)
				for _, group in ipairs(stale(page)) do mark(page, group) end
			end,
			addFolder = function(page)
				local storage, service = Model.db, page.app.service
				if type(service.pickFolder) ~= "function" then return end
				local path = service.pickFolder("Choose a Folder with Projects")
				if not path then return end
				storage.projectRoots = storage.projectRoots or {}
				for _, root in ipairs(storage.projectRoots) do if root == path then return end end
				table.insert(storage.projectRoots, path)
				if service.saveFolders then service.saveFolders("projects", storage.projectRoots) end
				page.app.rescan()
			end,
			-- The sidebar's badge: the build data found, whether or not the page was opened.
			badge = function(page)
				local bytes = 0
				for _, group in ipairs(groups(page, Projects.filters[1])) do bytes = bytes + group.bytes end
				return bytes > 0 and Format.size(bytes) or nil
			end,
		}, present = function(page, state)
			local model = Model.db
			Model.db.projectInfo = Model.db.projectInfo or {}
			local query = state.query or ""
			-- Nothing is listed until the scan has found the projects and git has
			-- told their state, one project at a time.
			local waiting = page.app.service.projectInfo ~= nil
			if model.scan.running then return {waiting = WAITING} end
			if waiting then
				for _, group in ipairs(groups(page, Projects.filters[1])) do
					if not Model.db.projectInfo[group.path] then return {computing = "Reading the state of your projects…"} end
				end
			end
			-- Rows are the groups themselves, so menus receive a project's
			-- artifacts. A project is marked when all its build folders are.
			local rows = groups(page, Projects.filters[page.filterIndex], query)
			for _, group in ipairs(rows) do
				group.id, group.detail = group.path, group.gitText
				group.subtitle = Format.tilde(group.path, model.home) .. " · " .. group.artifactText .. " · " .. group.ageText
				group.icon, group.color = "folder.fill", group.dirty and "systemOrange" or "systemGreen"
				if isMarked(page, group) then
					group.icon, group.color, group.subtitle = "checkmark.circle.fill", "systemBlue", "Marked for cleanup · " .. group.subtitle
				elseif included(page, group) then
					group.icon, group.color, group.subtitle = "folder.badge.checkmark", "systemBlue", "Included through marked folder · " .. group.subtitle
				end
			end
			local all, bytes = groups(page, Projects.filters[1], query), 0
			for _, group in ipairs(all) do bytes = bytes + group.bytes end
			return {lists = {projects = page.actions:annotate(rows)}, hidden = {projectsEmpty = #all > 0, projectsList = #all == 0},
				disabled = {markStale = #stale(page, query) == 0}, texts = {projectRoots = "Project folders: " .. rootsText(page) .. ".",
				projectsSummary = #all == 0 and "No project build folders found yet. Add the folders where you keep code."
					or (Format.size(bytes) .. " of build data in " .. Format.plural(#all, "project"))}}
		end})
end

return routes
