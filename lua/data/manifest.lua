-- The app manifest: one XML file that names an app's sections and pages.
-- The sidebar, the Go menu, the page set and the startup page all come from
-- it, where Diskmap kept three lists that had to agree.
--
--   <App name="Diskmap" startup="overview">
--   	<Section title="Developer">
--   		<Page id="xcode" title="Xcode" icon="hammer.circle.fill" color="systemBlue" key="9" />
--   		<Page id="music" title="Music Production" icon="pianokeys" route="workflow" workflow="music" />
--   	</Section>
--   </App>
--
-- A page is drawn by its route (lua/data/routes.lua): `route` names it, and
-- the page id is the route's name when it is omitted. Every other attribute
-- is kept in `page.attrs`, the route's `self.params` (`workflow="music"`).
-- `navigationTitle` and `navigationSubtitle` are what the title bar shows
-- for the page, as SwiftUI's `.navigationTitle` and `.navigationSubtitle`
-- (`title` names the page in the sidebar and the Go menu);
-- `sidebar="Dev tools"` is a shorter name for the sidebar row;
-- `listed="false"` keeps a page out of the sidebar and the Go menu (a page
-- opened from elsewhere). `arg="topic"` names the param a page's location
-- carries in its path, `/help/shortcuts` (lua/data/location.lua).
--
-- A `<Toolbar>` of `<ToolbarItem id label icon action validate placement>`
-- holds the window-wide actions (the window toolbar on macOS, the navigation
-- bar on iPhone). An item calls `action` on the page being shown and is
-- dimmed on a page that has no such method; `validate` names a page method
-- that says whether it is enabled now (`canCopy`).
--
-- `<App background="secondaryBackground">` is the color behind the pages
-- where they do not reach: on iPhone a page ends at the keyboard's top, and
-- this color fills behind the keyboard's rounded corners.
--
-- `<App routes="pages">` names the module of the app's routes, a module path
-- inside the app; it is `routes` when omitted. `<App controller="Controller">`
-- names a class of the app that coordinates the whole window -- a root
-- controller with services, scanning, sheets -- and replaces the framework's
-- launcher; it still takes its pages, sidebar rows and Go menu from this file.
local Manifest = {}

local function fail(message) error("manifest: " .. message, 0) end

function Manifest.parse(nodes)
	local root
	for _, node in ipairs(nodes) do
		if node.kind == "element" then
			if node.tag ~= "App" then fail("the document root must be <App>, not <" .. node.tag .. ">") end
			root = node
		end
	end
	if not root then fail("no <App> element") end
	local manifest = { name = root.attrs.name or "App", startup = root.attrs.startup, controller = root.attrs.controller,
		routes = root.attrs.routes or "routes", sections = {}, pages = {}, order = {}, toolbar = {},
		background = root.attrs.background }
	local function page(node, section)
		local attrs = node.attrs
		for _, key in ipairs({ "id", "title" }) do
			if not attrs[key] or attrs[key] == "" then fail("<Page> needs " .. key) end
		end
		if manifest.pages[attrs.id] then fail("page " .. attrs.id .. " is declared twice") end
		local entry = { id = attrs.id, title = attrs.title, icon = attrs.icon, color = attrs.color, key = attrs.key,
			route = attrs.route or attrs.id, section = section, listed = attrs.listed ~= "false", attrs = attrs }
		manifest.pages[entry.id] = entry
		table.insert(manifest.order, entry)
		if entry.listed then table.insert(section.pages, entry) end
	end
	local current = { pages = {} }
	table.insert(manifest.sections, current)
	for _, node in ipairs(root.children) do
		if node.kind == "element" then
			if node.tag == "Section" then
				current = { title = node.attrs.title, pages = {} }
				table.insert(manifest.sections, current)
				for _, child in ipairs(node.children) do
					if child.kind == "element" then
						if child.tag ~= "Page" then fail("<" .. child.tag .. "> inside <Section>; only <Page> belongs there") end
						page(child, current)
					end
				end
			elseif node.tag == "Toolbar" then
				for _, child in ipairs(node.children) do
					if child.kind == "element" then
						if child.tag ~= "ToolbarItem" then fail("<" .. child.tag .. "> inside <Toolbar>; only <ToolbarItem> belongs there") end
						for _, key in ipairs({ "id", "action" }) do
							if not child.attrs[key] or child.attrs[key] == "" then fail("<ToolbarItem> needs " .. key) end
						end
						table.insert(manifest.toolbar, child.attrs)
					end
				end
			elseif node.tag == "Page" then
				-- Pages before the first section lead the sidebar without a header.
				if #manifest.sections > 1 and current.title then
					current = { pages = {} }
					table.insert(manifest.sections, current)
				end
				page(node, current)
			else
				fail("<" .. node.tag .. "> is not part of the manifest; use Section, Page or Toolbar")
			end
		end
	end
	-- A section left with no listed page (pages after it that are unlisted) is
	-- no group in the sidebar or the Go menu.
	for index = #manifest.sections, 1, -1 do
		if #manifest.sections[index].pages == 0 then table.remove(manifest.sections, index) end
	end
	if #manifest.order == 0 then fail("the app has no pages") end
	local keys = {}
	for _, entry in ipairs(manifest.order) do
		if entry.key then
			if keys[entry.key] then fail("pages " .. keys[entry.key] .. " and " .. entry.id .. " share the key " .. entry.key) end
			keys[entry.key] = entry.id
		end
	end
	manifest.startup = manifest.startup or manifest.order[1].id
	if not manifest.pages[manifest.startup] then fail("startup page " .. manifest.startup .. " is not declared") end
	return manifest
end

-- Parses the manifest file at `path`.
function Manifest.load(path)
	local xml = require("ui.xml")
	return Manifest.parse(xml.parse(xml.source(path) or error("manifest: cannot read " .. path, 0)))
end

-- The launch options in `args` (the process arguments): `--page=<id>` and
-- `--isolated`.
function Manifest.options(args)
	local options = {}
	for _, value in pairs(args or {}) do
		if type(value) == "string" then
			local page = value:match("^%-%-page=(.+)$")
			if page then options.page = page end
			if value == "--isolated" then options.isolated = true end
		end
	end
	return options
end

return Manifest
