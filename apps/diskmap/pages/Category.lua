local Model = require("data.model")
local Categories = require("apps.diskmap.models.Categories")
local Items = require("apps.diskmap.models.Items")
local Format = require("apps.diskmap.helpers.Format")

-- One route for the eight sources: `<Page route="category" category="xcode">`.
-- Each page is the rows its source wrote (services/Sources.lua) in the
-- sections below, every row with its verdict, its owner and when it was
-- last written. Actions flag rows; nothing here touches the disk.
local routes = {}

local SECTIONS = {
	xcode = {
		{id = "derived", title = "DerivedData", detail = "Build products and indexes per project. Data of a project that no longer exists is safe; the rest Xcode rebuilds, more slowly, on the next build."},
		{id = "support", title = "Device Support", detail = "Debug symbols Xcode copied from each device OS version you debugged. The newest per platform is kept."},
		{id = "archives", title = "Archives", detail = "Shipped builds with their symbols, oldest first. Without an archive, crash reports for that version cannot be symbolicated."},
		{id = "caches", title = "Caches", detail = "What Xcode and the simulator rebuild when needed."},
		{id = "backups", title = "Device Backups", detail = "iPhone and iPad backups Finder keeps. Manage them in Finder."},
		{id = "tools", title = "Tools", detail = "Toolchains installed beside Xcode."},
	},
	simulators = {
		{id = "devices", title = "Devices", detail = "Each device's installed apps and data. Erasing resets a device; deleting removes it. Unavailable devices have no runtime left to boot."},
		{id = "runtimes", title = "Runtimes", detail = "The operating system images devices boot. One with no devices can go; Xcode downloads it again from Settings › Components."},
		{id = "caches", title = "Caches", detail = "What the simulator rebuilds when it next boots."},
	},
	projects = {
		{id = "builds", title = "Build Output", detail = "Folders a build tool made beside its project. Safe when the project has been idle for three months; otherwise the next build is slower without them."},
	},
	worktrees = {
		{id = "worktrees", title = "Linked Worktrees", detail = "Checkouts made beside a repository, by you or by a coding tool. Ready when every commit is on a remote and nothing is in progress."},
		{id = "missing", title = "Missing", detail = "Registered in Git but gone from the disk. Pruning removes the record; no files are involved."},
	},
	packages = {
		{id = "caches", title = "Download Caches", detail = "Packages a lockfile restores. The next install downloads what a project needs."},
		{id = "toolchains", title = "Toolchains", detail = "Installed language versions and package trees. Remove a version with the tool that installed it."},
	},
	editors = {
		{id = "vscode", title = "Visual Studio Code", detail = ""},
		{id = "zed", title = "Zed", detail = ""},
		{id = "cursor", title = "Cursor", detail = ""},
		{id = "jetbrains", title = "JetBrains", detail = ""},
	},
	ai = {
		{id = "codex", title = "Codex", detail = ""},
		{id = "claude", title = "Claude", detail = ""},
		{id = "opencode", title = "OpenCode", detail = ""},
		{id = "grok", title = "Grok", detail = ""},
		{id = "models", title = "Local Models", detail = "Model weights downloaded by local inference tools. Remove them with the tool; it downloads them again on demand."},
	},
	system = {
		{id = "volumes", title = "Volumes", detail = "The other volumes of the startup disk, by their own size. macOS manages all of them."},
		{id = "assets", title = "Downloaded System Assets", detail = "What macOS downloaded for Siri, dictation, documentation and the simulator. Turning a feature off lets macOS remove its assets."},
		{id = "caches", title = "Caches", detail = "One folder per app. An app rebuilds its cache; quit it first. A folder no installed app claims is noted as such."},
		{id = "logs", title = "Logs", detail = "Logs of your apps and of macOS. Old ones can go; the unified log is managed by macOS."},
		{id = "temporary", title = "Temporary Files", detail = "Scratch files of tools and apps. A tool still running would lose its working files."},
	},
}

local LIST = {rowHeight = 44}

local Category = {view = "pages/Category", queries = {rowMenu = true}}
routes.category = Category

function Category:init()
	self.rows = self:flow("Rows")
	self.category = assert(Categories:find(self.params.category), "page " .. self.id .. " names no category")
end

function Category:data()
	local now = os.time()
	local category = self.category
	local sections, count = {}, 0
	local lists = {}
	for _, section in ipairs(SECTIONS[category.id] or {}) do
		local rows = Items:inSection(category.id, section.id)
		if #rows > 0 then
			count = count + #rows
			local bytes, safe = 0, 0
			for _, row in ipairs(rows) do bytes = bytes + (row.bytes or 0); if row.verdict == "safe" then safe = safe + (row.bytes or 0) end end
			table.insert(sections, {id = section.id, title = section.title, detail = section.detail, listId = "list_" .. section.id,
				size = Format.size(bytes) .. (safe > 0 and (" · " .. Format.size(safe) .. " safe") or ""),
				height = #rows * LIST.rowHeight})
			lists["list_" .. section.id] = self.rows:present(rows, now)
		end
	end
	local bytes, safe, pending = category:totals()
	local measuring = Model.db.scan.pending[category.id] == true
	local subtitle
	if measuring and count == 0 then subtitle = "Measuring…"
	elseif count == 0 then subtitle = category.empty
	else subtitle = Format.plural(count, "item") .. " · " .. Format.size(bytes) .. (safe > 0 and (" · " .. Format.size(safe) .. " safe to remove") or "") end
	local note = self.app.sourceNote and self.app.sourceNote(category.id) or nil
	return {
		title = category.title, subtitle = subtitle, summary = category.summary,
		sections = sections, lists = lists, note = note or "", notice = Model.db.notice or "",
		hidden = {empty = count > 0 or measuring, measuring = not (measuring and count == 0), note = note == nil, notice = Model.db.notice == nil,
			removeSafe = safe == 0, addFolder = category.id ~= "projects" and category.id ~= "worktrees"},
		disabled = {removeSafe = safe == 0},
		emptyTitle = "Nothing Here", emptyText = category.empty,
	}
end

function Category:rowMenu(_, _, row) return self.rows:menu(row and Items:find(row.id) or nil) end
function Category:removeRow(_, _, row) if row then return self.rows:remove(Items:find(row.id) or row) end end
function Category:open(_, _, row)
	if row and row.path and row.state == "measured" and row.directory ~= false then self.app.show("folder", {path = row.path}) end
end
function Category:removeSafe() return self.rows:removeSafe(Items:inCategory(self.category.id)) end
function Category:measure() self.app.measure({self.category.id}) end

-- Projects and Worktrees search the folders people keep projects in; one
-- more can be added and is remembered.
function Category:addFolder()
	local path = self.app.service.pickFolder("Add a Folder of Projects")
	if not path then return end
	local folders = Model.db.folders
	for _, existing in ipairs(folders) do if existing == path then return end end
	table.insert(folders, path)
	self.app.service.saveFolders("projects", folders)
	self.app.measure({"projects", "worktrees"})
end

return routes
