-- Compose domain providers; IDs and exact paths form the ownership ledger.
local Catalog = {}
local providers = {
	(require("apps.diskmap.catalog.Applications")),
	(require("apps.diskmap.catalog.Developer")),
	(require("apps.diskmap.catalog.Documents")),
	(require("apps.diskmap.catalog.Media")),
	(require("apps.diskmap.catalog.SystemData")),
	(require("apps.diskmap.catalog.Backups")),
	(require("apps.diskmap.catalog.MacOS")),
	(require("apps.diskmap.catalog.Trash")),
	(require("apps.diskmap.catalog.Other")),
}
function Catalog.tree(home)
	local tree = {}
	for _, provider in ipairs(providers) do tree[#tree + 1] = provider() end
	local owners = {
		xcode = "com.apple.dt.Xcode", ["vscode-data"] = "com.microsoft.VSCode",
		["vscode-extensions"] = "com.microsoft.VSCode", cursor = "com.todesktop.230313mzl4w4u92",
		docker = "com.docker.docker", mail = "com.apple.mail", messages = "com.apple.MobileSMS",
	}
	local function resolve(rows)
		for _, row in ipairs(rows) do
			row.appIcon = owners[row.id]
			if row.path then row.path = row.path:gsub("^~", function() return home end) end
			if row.children then resolve(row.children) end
		end
	end
	resolve(tree)
	return tree
end
return Catalog
