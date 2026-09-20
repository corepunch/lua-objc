local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")

local VIEWS = "apps/diskmap/views/"

local LAYOUT = {
	sidebarWidth = 228,
	rightWidth = 330,
}

local NAV_ITEMS = {
	{ title = "Disk Map", icon = "chart.pie.fill", selected = true },
	{ title = "Suggestions", icon = "lightbulb" },
	{ title = "Large Files", icon = "doc.fill" },
	{ title = "Applications", icon = "app.fill" },
	{ title = "File Types", icon = "doc.on.doc.fill" },
}

local USAGE_COLORS = {
	"systemBlue", "systemPurple", "systemOrange", "systemYellow", "systemGray",
}

local CLEANABLE = {
	build = "Build artifacts — can be rebuilt",
	dist = "Build output — can be rebuilt",
	out = "Build output — can be rebuilt",
	node_modules = "npm packages — reinstall with npm install",
	[".cache"] = "Cache files — safe to delete",
	["__pycache__"] = "Python bytecode cache",
	vendor = "Vendored deps — reinstallable",
	Pods = "CocoaPods — reinstall with pod install",
	DerivedData = "Xcode build data — safe to delete",
	[".next"] = "Next.js cache — rebuilt on next build",
	target = "Build output — can be rebuilt",
	[".gradle"] = "Gradle cache — rebuilt on next build",
	xcuserdata = "Xcode user data — safe to delete",
	Downloads = "Downloads — likely stale installers",
}

local function humanPercent(value)
	return value >= 1 and string.format("%.0f%%", value) or "<1%"
end

local function render(template, data)
	return xml.renderFile(VIEWS .. template, data, ns)
end

local function suggestionsFor(tree)
	local result = {}
	for _, child in ipairs(tree.children) do
		if CLEANABLE[child.name] then
			result[#result + 1] = {
				name = child.name,
				size = Model.humanKb(child.kb),
				hint = CLEANABLE[child.name],
				path = child.path,
			}
		end
	end
	table.sort(result, function(a, b) return a.size > b.size end)
	return result
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		window = nil,
		refs = nil,
		history = {},
		forward = {},
		currentPath = nil,
		currentTree = nil,
		selectedNode = nil,
		nodeCache = {},
	}, Controller)
end

function Controller:cacheNodes(node)
	self.nodeCache[node.path] = node
	for _, child in ipairs(node.children) do self:cacheNodes(child) end
end

function Controller:selectNode(node)
	self.selectedNode = node
end

function Controller:goBack()
	if #self.history == 0 then return end
	table.insert(self.forward, self.currentPath)
	self:startScan(table.remove(self.history), true)
end

function Controller:goForward()
	if #self.forward == 0 then return end
	table.insert(self.history, self.currentPath)
	self:startScan(table.remove(self.forward), true)
end

function Controller:goUp()
	if not self.currentPath then return end
	local parent = self.currentPath:match("^(.+)/[^/]+$")
	if parent and parent ~= "" then self:startScan(parent) end
end

function Controller:reveal(path)
	ns.revealInFinder(path or self.currentPath)
end

function Controller:copyPath(path)
	ns.copyToClipboard(path or self.currentPath)
end

function Controller:openTerminal(path)
	os.execute(string.format("open -a Terminal %q", path or self.currentPath))
end

function Controller:makeDashboardData(tree, diskInfo)
	local total = math.max(tree.kb, 1)
	local breadcrumbs = {}
	for part in tree.path:gmatch("[^/]+") do breadcrumbs[#breadcrumbs + 1] = part end

	local usage, rows = {}, {}
	for i, child in ipairs(tree.children) do
		if i <= 5 then
			usage[#usage + 1] = {
				name = child.name,
				size = Model.humanKb(child.kb),
				color = USAGE_COLORS[((i - 1) % #USAGE_COLORS) + 1],
				width = math.max(4, math.floor(child.kb / total * 600)),
			}
		end
		rows[#rows + 1] = {
				name = child.name,
				size = Model.humanKb(child.kb),
				items = tostring(#child.children),
				percent = humanPercent(child.kb / total * 100),
				path = child.path,
				index = i,
			}
	end

	local data = {
		navItems = NAV_ITEMS,
		name = tree.name,
		path = tree.path,
		breadcrumbs = breadcrumbs,
		usage = usage,
		rows = rows,
		items = tostring(Model.countItems(tree)),
		folderCount = tostring(#tree.children),
		total = Model.humanKb(tree.kb),
		free = diskInfo and Model.humanKb(diskInfo.freeKb) or "—",
		suggestions = suggestionsFor(tree),
		diskTotal = diskInfo and Model.humanKb(diskInfo.totalKb) or Model.humanKb(tree.kb),
		__baseDir = VIEWS,
	}
	data.actions = {
		back = function() self:goBack() end,
		forward = function() self:goForward() end,
		up = function() self:goUp() end,
		copyPath = function() self:copyPath(tree.path) end,
		openTerminal = function() self:openTerminal(tree.path) end,
		reveal = function() self:reveal(tree.path) end,
	}
	for i, row in ipairs(rows) do
		data.actions["open_" .. i] = function() self:startScan(row.path) end
	end
	for i, suggestion in ipairs(data.suggestions) do
		if i > 3 then break end
		data.actions["review_" .. i] = function() self:startScan(suggestion.path) end
	end
	return data
end

function Controller:showContent(view)
	self.refs.content:clearContainer()
	self.refs.content:add(view)
	self.refs.content:layout()
end

function Controller:displayTree(tree)
	self.currentTree = tree
	local data = self:makeDashboardData(tree, Model.diskSpace(self.currentPath))
	local view = render("Dashboard.etlua", data)
	self:showContent(view)
end

function Controller:startScan(rootPath, isNav)
	if not isNav and self.currentPath then
		table.insert(self.history, self.currentPath)
		self.forward = {}
	end
	self.currentPath = rootPath
	self.selectedNode = nil
	self.currentTree = nil
	local cached = self.nodeCache[rootPath]
	if cached and #cached.children > 0 then
		self:displayTree(cached)
		return
	end

	local loading = render("Loading.etlua", { message = "Scanning " .. rootPath .. " …", __baseDir = VIEWS })
	self:showContent(loading)
	local handle = Model.startScan(rootPath, 5)
	local controller = self
	ns.async(function()
		ns.sleep(0.2)
		while not Model.isDone(handle) do ns.sleep(0.5) end
		local tree = Model.parseTree(handle)
		if not tree then
			controller:showContent(render("Loading.etlua", { message = "No data found.", __baseDir = VIEWS }))
			return
		end
		controller:cacheNodes(tree)
		controller:displayTree(tree)
	end)
end

function Controller:rescan()
	if not self.currentPath then return end
	self.nodeCache[self.currentPath] = nil
	self:startScan(self.currentPath)
end

function Controller:createMenuBar()
	local controller = self
	ns.MenuItem { menu = "File", title = "Reveal in Finder", keyEquivalent = "r", modifiers = { "command", "shift" }, action = function() controller:reveal(controller.selectedNode and controller.selectedNode.path) end }
	ns.MenuItem { menu = "File", title = "Copy Path", keyEquivalent = "c", modifiers = { "command", "shift" }, action = function() controller:copyPath(controller.selectedNode and controller.selectedNode.path) end }
	ns.MenuItem { menu = "Go", title = "Back", keyEquivalent = "[", modifiers = { "command" }, action = function() controller:goBack() end }
	ns.MenuItem { menu = "Go", title = "Forward", keyEquivalent = "]", modifiers = { "command" }, action = function() controller:goForward() end }
	ns.MenuItem { menu = "View", title = "Rescan", keyEquivalent = "r", modifiers = { "command" }, action = function() controller:rescan() end }
end

function Controller:createWindow()
	local rootPath = (arg and arg[1]) or os.getenv("HOME") or "/"
	local cfg, refs = render("Window.etlua", {
		navItems = NAV_ITEMS,
		rootPath = rootPath,
		__baseDir = VIEWS,
	})
	self.refs = refs
	self.window = ns.Window(cfg)
	self:createMenuBar()
	self:startScan(rootPath)
end

return Controller
