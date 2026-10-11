local Volumes = {}

-- The volumes of the startup container from `diskutil apfs list -plist`:
-- {name, role, bytes}, in the order the plist lists them. `container`
-- is the reference `diskutil info -plist /` gives (disk3); without it every
-- container's volumes are returned.
function Volumes.parse(plist, container)
	local rows = {}
	for _, entry in ipairs(type(plist) == "table" and plist.Containers or {}) do
		if not container or entry.ContainerReference == container then
			for _, volume in ipairs(entry.Volumes or {}) do
				local role = type(volume.Roles) == "table" and volume.Roles[1] or "Data"
				table.insert(rows, {name = volume.Name or role, role = role, bytes = tonumber(volume.CapacityInUse) or 0, device = volume.DeviceIdentifier})
			end
		end
	end
	return rows
end

-- What each volume role is, for the System Data page.
Volumes.roles = {
	Preboot = {name = "Preboot", what = "Boot files, the FileVault unlock screen and the cryptexes that carry Safari, Rosetta and the shared code cache. Its files are clones, so adding them up overstates it; this is the volume's own size."},
	Recovery = {name = "Recovery", what = "The recoveryOS used to reinstall macOS or repair the disk."},
	VM = {name = "Swap", what = "Memory swapped to disk under memory pressure. A restart releases it."},
	Update = {name = "Update", what = "Where Software Update prepares a macOS update; gigabytes while one is prepared or stuck."},
	System = {name = "macOS", what = "The sealed, read-only system volume: macOS itself."},
}

return Volumes
