-- The welcome tour: shown on start until the person turns that off, and
-- from Help > Diskmap Tour. Each page is one element of a page of Diskmap
-- and what it is for. The screenshots come from the showcase disk
-- (tour/capture.lua), never from this Mac, cropped to the tour's image box
-- and captured in light and dark to follow the appearance.
local Tour = {}

local IMAGES = "apps/diskmap/tour/"

Tour.pages = {
	{id = "overview", title = "Where your space goes",
		text = "The Overview sorts your disk into categories. A ≥ before a size means at least that much, because some folders could not be read. Below this card, Diskmap says what it could not measure, and why."},
	{id = "map", title = "Explore by size",
		text = "The Map lists every category with its size and draws it as rings, with the folders inside around it. Hover for details and click a group to look inside. Folder Map does the same for any folder you open."},
	{id = "largest", title = "The largest items",
		text = "Largest Items ranks every location Diskmap knows, from all categories, by size. Open an item's menu to show it in the Finder, review it, or keep it out of suggestions."},
	{id = "files", title = "Big and forgotten files",
		text = "Large Files finds files over 50 MB, those you have not opened for a year, and your own documents you could move to the Trash. Switch between them above the list."},
	{id = "kinds", title = "Kinds of files",
		text = "File Types groups files by extension, the way the Finder's Kind column does, so you can see whether videos, disk images or app data take the most space. Open a kind to see its largest files."},
	{id = "applications", title = "Apps and their data",
		text = "Applications shows each app with the data it keeps in your Library, the apps you have not opened for months, and leftovers of apps you already deleted."},
	{id = "cleanup", title = "Clean up safely",
		text = "Recommendations list what can go. Rebuildable items are caches their apps make again; items to review may hold your work. Nothing moves until you review it, and it goes to the Trash."},
	{id = "developer", title = "Developer tools",
		text = "If you write software, Developer pages measure Xcode, simulators, package caches and projects. A green arrow marks what the tools rebuild; an eye marks what to look at first."},
	{id = "disks", title = "Your disk and volumes",
		text = "Disks & Volumes shows the drive's health and encryption, and how the volumes of your startup disk share its space."},
	{id = "guide", title = "Space macOS manages",
		text = "Some space belongs to macOS, such as Siri and Apple Intelligence models. Do not delete it by hand: its rows say which setting to change, and the Storage Guide explains what each kind of storage is and what to do about it."},
}

for index, page in ipairs(Tour.pages) do
	page.index = index
	page.image = IMAGES .. page.id .. "-light.jpg"
	page.darkImage = IMAGES .. page.id .. "-dark.jpg"
	page.counter = index .. " of " .. #Tour.pages
end

return Tour
