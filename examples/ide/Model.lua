local ns = require("AppKit")
local bridge = require("AppKitNative")

local Model = {}

local extToLanguage = {
	lua = "lua",
	[".lua"] = "lua",
	m = "objective-c",
	mm = "objective-c",
	h = "objective-c",
	c = "c",
	cpp = "c++",
	swift = "swift",
	js = "javascript",
	ts = "typescript",
	json = "json",
	xml = "xml",
	html = "html",
	css = "css",
	md = "markdown",
	[".md"] = "markdown",
	txt = "text",
	[".txt"] = "text",
	sh = "shell",
	py = "python",
}

function Model.languageForPath(path)
	local ext = path:match("%.([^.]+)$")
	if ext then
		return extToLanguage[ext] or extToLanguage["." .. ext] or "text"
	end
	return "text"
end

function Model.readFile(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	return content
end

function Model.buildTree(entries, parentPath)
	local tree = {}
	for _, entry in ipairs(entries) do
		local node = { name = entry.name }
		local fullPath = parentPath and (parentPath .. "/" .. entry.name) or entry.name
		if entry.children and #entry.children > 0 then
			node.children = Model.buildTree(entry.children, fullPath)
		else
			node.path = fullPath
		end
		tree[#tree + 1] = node
	end
	table.sort(tree, function(a, b)
		if a.children and not b.children then return true end
		if not a.children and b.children then return false end
		return a.name < b.name
	end)
	return tree
end

function Model.readDirectory(path, depth)
	local entries = ns.readDirectory(path, depth or 3)
	if not entries then return {} end
	return Model.buildTree(entries, path)
end

return Model
