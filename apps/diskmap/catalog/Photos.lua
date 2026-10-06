local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("photos", "Photos", "The Photos library and other pictures. Manage the library in Photos.", "photo.fill", "systemOrange", {
		-- Nested in Pictures, measured on its own: it is usually the largest thing on a personal Mac.
		item("photos-library", "Photos library", "Originals, edits and previews of the photos in Photos", "~/Pictures/Photos Library.photoslibrary",
			{mediaAccess = true, nature = "personal", remover = "owner", threshold = 20e9, advice = "With iCloud Photos, turn on Photos › Settings › iCloud › Optimize Mac Storage: originals stay in iCloud and only smaller versions are kept here. Without it, delete photos in Photos and empty its Recently Deleted album."}),
		item("pictures", "Pictures", "Photo libraries and image files", "~/Pictures", {mediaAccess = true, nature = "personal"}),
	})
end
