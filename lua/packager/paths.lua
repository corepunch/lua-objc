--[[
  Packager path mapping, jail, and change-kind classification.
  Used by src/packager/packager.m (dofile) and tests/packager.test.lua.
]]

local M = {}

local ASSET_EXT = {
	png = true, jpg = true, jpeg = true, gif = true, webp = true,
	svg = true, json = true, zil = true, txt = true, md = true,
}

local MODULES = {
	UIKit = "lua/embedded/UIKit.lua",
	["ui.xml"] = "lua/ui/xml.lua",
	["ui.viewdesc"] = "lua/ui/viewdesc.lua",
	etlua = "lua/etlua.lua",
	["vendor.etlua.etlua"] = "lua/vendor/etlua/etlua.lua",
	App = "lua/App.lua",
	TestKit = "lua/TestKit.lua",
	["packager.paths"] = "lua/packager/paths.lua",
}

local NATIVE = {
	ns = true,
	UIKitNative = true,
	AppKit = true,
	AppKitNative = true,
	package = true,
}

local function split(path)
	local parts = {}
	for seg in (path:gsub("\\", "/") .. "/"):gmatch("([^/]*)/") do
		if seg == ".." then
			if #parts == 0 then return nil end
			table.remove(parts)
		elseif seg ~= "" and seg ~= "." then
			parts[#parts + 1] = seg
		end
	end
	return parts
end

function M.normalize(path)
	if type(path) ~= "string" or path == "" then return nil end
	if path:match("^/") or path:match("^%a:[/\\]") then return nil end
	local parts = split(path)
	if not parts then return nil end
	return table.concat(parts, "/")
end

function M.jail(root, rel)
	local norm = M.normalize(rel)
	if not norm then return nil, "escape" end
	local rootNorm = M.normalize(root) or root:gsub("\\", "/"):gsub("/$", "")
	-- When root is absolute, keep it as the prefix and only jail `rel`.
	if tostring(root):sub(1, 1) == "/" then
		rootNorm = tostring(root):gsub("/$", "")
		local full = rootNorm .. "/" .. norm
		return full, norm
	end
	return rootNorm .. "/" .. norm, norm
end

function M.kind(path)
	path = tostring(path):gsub("\\", "/")
	local base = path:match("([^/]+)$") or path
	if base == "Model.lua" then return "model" end
	if base == "init.lua" then return "init" end
	if path:match("%.etlua$") then return "view" end
	if path:match("Controller%.lua$") then return "controller" end
	if path:match("%.lua$") then return "runtime" end
	local ext = (base:match("%.([^.]+)$") or ""):lower()
	if ASSET_EXT[ext] then return "asset" end
	return "other"
end

function M.contentType(path)
	local ext = ((tostring(path):match("%.([^.]+)$")) or ""):lower()
	if ext == "lua" or ext == "etlua" then return "text/plain; charset=utf-8" end
	if ext == "png" then return "image/png" end
	if ext == "jpg" or ext == "jpeg" then return "image/jpeg" end
	if ext == "gif" then return "image/gif" end
	if ext == "webp" then return "image/webp" end
	if ext == "svg" then return "image/svg+xml" end
	if ext == "json" then return "application/json" end
	return "application/octet-stream"
end

function M.moduleRel(name)
	if type(name) ~= "string" or name == "" then return nil, "empty" end
	if NATIVE[name] then return nil, "native" end
	if MODULES[name] then return MODULES[name] end
	return (name:gsub("%.", "/")) .. ".lua"
end

function M.moduleCandidates(name)
	local rel, err = M.moduleRel(name)
	if not rel then return nil, err end
	if MODULES[name] then return { rel } end
	return { rel, "lua/" .. rel, "examples/" .. rel }
end

function M.watched(path)
	local kind = M.kind(path)
	if kind == "other" then return false end
	if path:match("^build/") or path:match("^%.git/") then return false end
	if path:match("^third_party/") or path:match("^src/") or path:match("^ios/") then
		return false
	end
	return true
end

M.MODULES = MODULES
M.NATIVE = NATIVE
return M
