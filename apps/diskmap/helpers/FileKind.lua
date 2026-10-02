local Kinds = require("apps.diskmap.knowledge.FileKinds")
local FileKind = {}

-- Folders that are documents to Finder. A file inside one belongs to its app
-- (a Photos library, an Xcode archive, a virtual machine), so Diskmap never
-- offers to trash it on its own.
local PACKAGES = {"app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
	"logicx", "band", "xcarchive", "bundle", "framework", "lrdata", "sparsebundle", "pvm", "utm", "vmwarevm",
	"aplibrary", "migratedphotolibrary", "xcodeproj", "xcworkspace", "playground", "rtfd", "pages", "numbers", "key"}
-- The package extensions as a set.
FileKind.packages = {}
for _, extension in ipairs(PACKAGES) do FileKind.packages[extension] = true end

-- Whether a file or folder name is a package Finder shows as one document.
function FileKind.isPackage(name)
	local extension = (name or ""):match("[^/]%.([^./]+)$")
	return extension ~= nil and FileKind.packages[extension:lower()] == true
end

-- A kind by a lower-case extension, and the kind of everything else.
FileKind.byExtension = {}
for _, kind in ipairs(Kinds) do
	for _, extension in ipairs(kind.extensions) do FileKind.byExtension[extension] = kind end
end
FileKind.other = Kinds[#Kinds]

function FileKind.of(path)
	local extension = (path or ""):match("[^/]%.([^./]+)$")
	return extension and FileKind.byExtension[extension:lower()] or FileKind.other
end
function FileKind.byId(id)
	for _, kind in ipairs(Kinds) do if kind.id == id then return kind end end
end

return FileKind
