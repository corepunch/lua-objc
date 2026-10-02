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
-- `class` is a module path inside the app, `view` a template in views/,
-- `controller` a class in controllers/ for a page that coordinates (a sheet,
-- a batch flow). A model's dependencies are in its own file, not here.
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
	local manifest = { name = root.attrs.name or "App", startup = root.attrs.startup,
		models = {}, sections = {}, pages = {}, order = {} }
	local function page(node, section)
		for _, key in ipairs({ "id", "title", "view", "model" }) do
			if not node.attrs[key] or node.attrs[key] == "" then fail("<Page> needs " .. key) end
		end
		local attrs = node.attrs
		if manifest.pages[attrs.id] then fail("page " .. attrs.id .. " is declared twice") end
		local entry = { id = attrs.id, title = attrs.title, icon = attrs.icon, color = attrs.color, key = attrs.key,
			view = attrs.view, model = attrs.model, controller = attrs.controller, section = section }
		manifest.pages[entry.id] = entry
		table.insert(manifest.order, entry)
		table.insert(section.pages, entry)
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
	if #manifest.sections[1].pages == 0 then table.remove(manifest.sections, 1) end
	if #manifest.order == 0 then fail("the app has no pages") end
	local keys = {}
	for _, entry in ipairs(manifest.order) do
		if not manifest.models[entry.model] then
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
