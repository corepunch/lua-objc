local Model = require("apps.diskmap.Model")
local Volumes = {}

-- What each APFS volume role holds, in the words the Storage Guide uses.
Volumes.roles = {
	System = {name = "macOS", icon = "lock.shield.fill", color = "systemGray", detail = "The sealed, read-only operating system"},
	Data = {name = "Your data", icon = "person.crop.circle.fill", color = "systemBlue", detail = "Apps, files, settings and caches"},
	Preboot = {name = "Preboot", icon = "power", color = "systemOrange", detail = "Boot files, cryptexes and staged updates"},
	Recovery = {name = "Recovery", icon = "lifepreserver.fill", color = "systemGreen", detail = "The recoveryOS used to repair or reinstall macOS"},
	VM = {name = "Swap", icon = "memorychip.fill", color = "systemPurple", detail = "Memory paged out to disk"},
	Update = {name = "Update", icon = "arrow.down.circle.fill", color = "systemTeal", detail = "Software update staging"},
	Hardware = {name = "Hardware", icon = "cpu.fill", color = "systemGray", detail = "Firmware and hardware data"},
	xART = {name = "xART", icon = "key.fill", color = "systemGray", detail = "Secure Enclave anti-replay data"},
}

local function yes(value) return value == true or value == "Yes" or value == "yes" end

-- Health facts from `diskutil info -plist /`, stated the way Disk Utility
-- states them. Unknown values are omitted, never guessed.
function Volumes.health(info)
	if type(info) ~= "table" then return {} end
	local rows = {}
	local smart = info.SMARTStatus
	if smart then
		local verified = smart == "Verified"
		table.insert(rows, {id = "smart", title = "Health", value = verified and "Verified" or smart,
			icon = verified and "checkmark.seal.fill" or "exclamationmark.triangle.fill", color = verified and "systemGreen" or "systemOrange",
			detail = verified and "The drive reports no SMART failures." or "The drive reports a SMART problem. Back up now and run First Aid in Disk Utility."})
	end
	if info.FileVault ~= nil then
		table.insert(rows, {id = "encryption", title = "Encryption", value = yes(info.FileVault) and "FileVault on" or "FileVault off",
			icon = yes(info.FileVault) and "lock.fill" or "lock.open.fill", color = yes(info.FileVault) and "systemBlue" or "systemOrange",
			detail = yes(info.FileVault) and "Erasing this disk makes its data unrecoverable without a secure wipe." or "Turn on FileVault in Privacy & Security to protect this disk."})
	end
	if info.Sealed ~= nil then
		table.insert(rows, {id = "sealed", title = "System", value = yes(info.Sealed) and "Sealed" or "Not sealed",
			icon = yes(info.Sealed) and "checkmark.shield.fill" or "exclamationmark.shield.fill", color = yes(info.Sealed) and "systemGreen" or "systemOrange",
			detail = yes(info.Sealed) and "macOS is cryptographically verified at every start." or "The system volume is not sealed; startup security may be reduced."})
	end
	local kind = {}
	if info.SolidState ~= nil then table.insert(kind, yes(info.SolidState) and "SSD" or "Hard disk") end
	if info.BusProtocol then table.insert(kind, info.BusProtocol) end
	if info.FilesystemUserVisibleName or info.FilesystemName then table.insert(kind, info.FilesystemUserVisibleName or info.FilesystemName) end
	if #kind > 0 then
		table.insert(rows, {id = "device", title = "Drive", value = kind[1], icon = "internaldrive.fill", color = "systemGray",
			detail = table.concat(kind, " · ") .. (yes(info.SolidState) and ". SSDs never need defragmenting." or "")})
	end
	return rows
end

-- APFS volumes of the startup container, largest first, from
-- `diskutil apfs list -plist`. Every volume draws on one shared pool.
function Volumes.apfs(list, containerReference)
	local containers = type(list) == "table" and list.Containers or nil
	if type(containers) ~= "table" then return nil end
	local container = containers[1]
	for _, candidate in ipairs(containers) do
		if candidate.ContainerReference == containerReference then container = candidate end
	end
	if not container then return nil end
	local rows, used = {}, 0
	for _, volume in ipairs(container.Volumes or {}) do
		local role = type(volume.Roles) == "table" and volume.Roles[1] or nil
		local known = Volumes.roles[role or ""] or {name = role or "Volume", icon = "externaldrive.fill", color = "systemGray", detail = "Additional volume"}
		local bytes = volume.CapacityInUse or 0
		used = used + bytes
		table.insert(rows, {id = volume.DeviceIdentifier or volume.Name, name = volume.Name or known.name,
			subtitle = known.name .. " · " .. known.detail, icon = known.icon, color = known.color, bytes = bytes, size = Model.size(bytes),
			detail = volume.DeviceIdentifier or ""})
	end
	table.sort(rows, function(a, b) return a.bytes > b.bytes end)
	local capacity = container.CapacityCeiling or 0
	for _, row in ipairs(rows) do
		row.relative = capacity > 0 and row.bytes / capacity or 0
		local percent = capacity > 0 and row.bytes * 100 / capacity or 0
		row.shareText = percent > 0 and percent < 1 and "<1%" or string.format("%d%%", math.floor(percent + 0.5))
	end
	return {rows = rows, capacity = capacity, free = container.CapacityFree or 0, used = used,
		reference = container.ContainerReference}
end

-- Other mounted volumes with their capacity bars.
function Volumes.external(volumes)
	local rows = {}
	for _, volume in ipairs(volumes or {}) do
		local total, free = volume.totalBytes or 0, volume.freeBytes or 0
		table.insert(rows, {id = volume.path, path = volume.path, name = volume.name,
			subtitle = (volume.filesystem and (volume.filesystem .. " · ") or "") .. Model.size(free) .. " free of " .. Model.size(total),
			icon = volume.removable and "externaldrive.fill" or "externaldrive.connected.to.line.below.fill", color = "systemGray",
			bytes = total - free, size = Model.size(total - free), relative = total > 0 and (total - free) / total or 0,
			shareText = total > 0 and string.format("%d%% used", math.floor((total - free) * 100 / total + 0.5)) or "", detail = ""})
	end
	return rows
end

return Volumes
