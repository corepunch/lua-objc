-- The app manifest: one XML file that names an app's models, sections and
-- pages. The sidebar, the Go menu, the page set and the startup page all
-- come from it, where Diskmap kept three lists that had to agree.
--
--   <App name="Diskmap" startup="overview">
--   	<Model id="xcode" class="models.Xcode" />
--   	<Section title="Free Up Space">
--   		<Page id="xcode" title="Xcode" icon="hammer.circle.fill" color="systemBlue"
--   		      key="9" view="Page" model="xcode" />
--   		<Page id="simulators" title="Simulators" icon="iphone" view="Simulators"
--   		      model="simulators" controller="SimulatorsController" />
--   	</Section>
--   </App>
--
-- `<App controller="Controller">` names a class of the app (a module path
-- inside it) that coordinates the whole window — a root controller with
-- services, scanning, sheets — and replaces the framework's launcher; it still
-- takes its pages, sidebar rows and Go menu from this file.
--
-- `class` is a module path inside the app, `view` a template in views/,
-- `controller` a class in controllers/ for a page that coordinates (a sheet,
-- a batch flow). A page with a controller may omit `view` and `model`: the
-- controller is its code-behind and owns what it shows. A model's
-- dependencies are in its own file, not here.
--
-- Any other attribute of a page (`workflow="developer"`, `header="..."`) is
-- kept in `page.attrs` for the app's controllers. `sidebar="Dev tools"` is a
-- shorter name for the sidebar row; `listed="false"` keeps a page out of the
-- sidebar and the Go menu (a page opened from elsewhere).
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
		models = {}, sections = {}, pages = {}, order = {} }
	local function page(node, section)
		local attrs = node.attrs
		for _, key in ipairs({ "id", "title" }) do
			if not attrs[key] or attrs[key] == "" then fail("<Page> needs " .. key) end
		end
		if not attrs.controller and (not attrs.view or not attrs.model) then
			fail("page " .. attrs.id .. " needs view and model, or a controller")
		end
		if manifest.pages[attrs.id] then fail("page " .. attrs.id .. " is declared twice") end
		local entry = { id = attrs.id, title = attrs.title, icon = attrs.icon, color = attrs.color, key = attrs.key,
			view = attrs.view, model = attrs.model, controller = attrs.controller, section = section,
			listed = attrs.listed ~= "false", attrs = attrs }
		manifest.pages[entry.id] = entry
		table.insert(manifest.order, entry)
		if entry.listed then table.insert(section.pages, entry) end
	end
	local current = { pages = {} }
	table.insert(manifest.sections, current)
	for _, node in ipairs(root.children) do
		if node.kind == "element" then
			if node.tag == "Model" then
				if not node.attrs.id or not node.attrs.class then fail("<Model> needs id and class") end
				if manifest.models[node.attrs.id] then fail("model " .. node.attrs.id .. " is declared twice") end
				manifest.models[node.attrs.id] = node.attrs.class
			elseif node.tag == "Section" then
				current = { title = node.attrs.title, pages = {} }
				table.insert(manifest.sections, current)
				for _, child in ipairs(node.children) do
					if child.kind == "element" then
						if child.tag ~= "Page" then fail("<" .. child.tag .. "> inside <Section>; only <Page> belongs there") end
						page(child, current)
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
				fail("<" .. node.tag .. "> is not part of the manifest; use Model, Section or Page")
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
		if entry.model and not manifest.models[entry.model] then
			fail("page " .. entry.id .. " names the model " .. entry.model .. ", which the manifest does not declare")
		end
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
