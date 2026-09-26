local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Developer = {}

-- Developer tools grouped by the decision a developer makes about them. Each
-- tile names a catalog resource (leaf or group) and the Diskmap destination
-- that manages it; nothing here grants removal on its own. `open` is either a
-- dedicated sheet (simulators, sdks) or a category to review.
Developer.tiles = {
	{id = "simulators", title = "Simulator devices", icon = "iphone", color = "systemBlue", open = "simulators",
		actionTitle = "Manage Devices…",
		detail = "Apps and data inside each simulator. Erase or delete devices you no longer test on."},
	{id = "runtimes", title = "Simulator runtimes", icon = "iphone.gen3", color = "systemBlue", open = "runtimes",
		actionTitle = "Review Runtimes…",
		detail = "iOS, watchOS and visionOS images. Remove old ones in Xcode › Settings › Components."},
	{id = "xcode-app", title = "Xcode & SDKs", icon = "hammer.fill", color = "systemBlue", open = "sdks",
		actionTitle = "Show SDKs…",
		detail = "The Xcode app and the SDKs bundled inside it. Remove only by uninstalling that Xcode."},
	{id = "derived", title = "DerivedData", icon = "gearshape.2.fill", color = "systemGreen", open = "xcode",
		actionTitle = "Review…",
		detail = "Build products and indexes. Safe to rebuild; the next build takes longer."},
	{id = "devices", title = "Device support", icon = "cable.connector", color = "systemTeal", open = "xcode",
		actionTitle = "Review…",
		detail = "Debug symbols copied from connected devices. Xcode copies them again when needed."},
	{id = "archives", title = "Archives", icon = "archivebox.fill", color = "systemOrange", open = "xcode",
		actionTitle = "Review…",
		detail = "Shipped builds and their debug symbols. Keep archives you may need to symbolicate."},
	{id = "packages", title = "Package managers", icon = "shippingbox", color = "systemOrange", open = "packages",
		actionTitle = "Review…",
		detail = "npm, pip, Homebrew, CocoaPods, Cargo and friends. Download caches refill on demand."},
	{id = "containers", title = "Containers & VMs", icon = "shippingbox.fill", color = "systemOrange", open = "containers",
		actionTitle = "Review…",
		detail = "Docker, Colima and virtual machines. Prune from the owning tool; disks may hold databases."},
	{id = "ai-tools", title = "AI coding tools", icon = "terminal", color = "systemIndigo", open = "ai-tools",
		actionTitle = "Review…",
		detail = "Codex, Claude Code, Cursor and others. Caches are separated from sessions and worktrees."},
}

local measured = Categories.row

-- Tile presentation in catalog order, with each tile's measured size and a
-- share bar relative to the largest tile. Tiles whose resource is absent from
-- the catalog are omitted rather than shown as zero.
function Developer.presentation(model)
	local tiles, largest = {}, 0
	for index, tile in ipairs(Developer.tiles) do
		local row = measured(model, tile.id)
		if row then
			local value = {index = index, id = tile.id, title = tile.title, icon = tile.icon, color = tile.color,
				detail = tile.detail, actionTitle = tile.actionTitle, open = tile.open,
				size = row.size, bytes = row.bytes or 0, calculating = row.calculating == true}
			largest = math.max(largest, value.bytes)
			table.insert(tiles, value)
		end
	end
	for _, tile in ipairs(tiles) do tile.relative = largest > 0 and tile.bytes / largest or 0 end
	local developer = measured(model, "developer")
	local agents = measured(model, "ai-tools")
	local bytes = (developer and developer.bytes or 0) + (agents and agents.bytes or 0)
	return {tiles = tiles, total = Model.size(bytes), bytes = bytes,
		calculating = (developer and developer.calculating) or (agents and agents.calculating) or false}
end

return Developer
