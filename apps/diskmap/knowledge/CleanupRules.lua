-- Product review thresholds, not claims about normal size or guaranteed reclaimable space.
-- Rule IDs map to catalog ownership; no rule grants additional deletion authority.
local Rules = {}
local function rule(ids, threshold, priority, advice)
	for _, id in ipairs(ids) do Rules[id] = {threshold = threshold, priority = priority, advice = advice} end
end
rule({"derived"}, 1e9, 1, "Build products and indexes can be regenerated. Quit Xcode before reviewing this cache.")
rule({"npm", "pip", "brew"}, 500e6, 1, "Downloaded packages can be fetched again. Review this cache after closing the owning package manager.")
rule({"simulators"}, 5e9, 2, "Review unused simulator devices in Xcode. Removing a device also removes its installed test apps and data.")
rule({"runtimes", "runtimes-legacy"}, 2e9, 2, "Review optional simulator runtimes in Xcode. Keep versions required by your projects.")
rule({"devices"}, 2e9, 2, "Review support files for devices you still debug. Keep symbols needed by current development work.")
rule({"docker", "colima", "parallels"}, 10e9, 3, "Review unused environments in the owning tool. Virtual disks and volumes can contain databases and personal work.")
rule({"downloads"}, 2e9, 3, "Review downloaded installers and archives in Finder. Keep personal files and anything you cannot download again.")
rule({"archives"}, 5e9, 4, "Review old releases in Xcode Organizer. Archives and debug symbols may be irreplaceable; back them up first.")
rule({"device-backups"}, 10e9, 4, "Review old device backups in Finder. Keep the restore points you still need.")
rule({"vscode-cache", "vscode-cached-data", "vscode-gpu-cache", "jetbrains"}, 1e9, 3, "Review generated editor data using the editor’s own storage controls. Preserve settings and recovery data.")
return Rules
