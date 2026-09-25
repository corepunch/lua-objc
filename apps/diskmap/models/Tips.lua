local Tips = {}
function Tips.forInventory(model, disk)
	local tips = {}
	if (model.scan.errors or 0) > 0 then
		table.insert(tips, {id = "access", icon = "lock.shield", title = "Some files could not be measured",
			text = tostring(model.scan.errors) .. " filesystem read issues were reported. Full Disk Access may improve coverage; some locations can still be unavailable. Refresh to retry. The unassigned amount is not a cleanup estimate.",
			action = "settings", actionTitle = "Review access options"})
	end
	if disk and disk.totalKb > 0 and disk.freeKb / disk.totalKb < 0.1 then
		table.insert(tips, {id = "capacity", icon = "externaldrive.badge.exclamationmark", title = "Available space is low",
			text = "Less than 10% of this disk is available. Review the measured candidates on this page and back up personal data before removing anything."})
	end
	local count = 0; for _, kept in pairs(model.kept) do if kept then count = count + 1 end end
	if count > 0 then
		table.insert(tips, {id = "kept", icon = "checkmark.shield", title = "Kept resources stay protected",
			text = tostring(count) .. " resources are marked Keep. Their descendants are excluded from cleanup suggestions.", action = "storage", actionTitle = "Browse resources"})
	end
	table.insert(tips, {id = "system", icon = "shield.lefthalf.filled", title = "macOS manages system storage",
		text = "Preboot, Recovery and local snapshots are system managed. File scans cannot attribute exclusive snapshot allocation. No manual cleanup is offered.", action = "system", actionTitle = "Learn about system storage"})
	return tips
end
return Tips
