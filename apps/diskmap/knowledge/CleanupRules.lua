-- Product review thresholds, not claims about normal size or guaranteed reclaimable space.
-- Rule IDs map to catalog ownership; no rule grants additional deletion authority.
local Rules = {}
local function rule(ids, threshold, priority, advice)
	for _, id in ipairs(ids) do Rules[id] = {threshold = threshold, priority = priority, advice = advice} end
end
rule({"derived"}, 1e9, 1, "Build products and indexes can be regenerated, though the next build takes longer. Quit Xcode before reviewing this cache.")
rule({"npm", "pip", "brew"}, 500e6, 1, "Downloaded packages can be fetched again. Review this cache after closing the owning package manager.")
rule({"simulators"}, 5e9, 2, "Review unused simulator devices. Removing a device also removes its installed test apps and data.")
rule({"devices"}, 2e9, 2, "Review support files for devices you still debug. Keep symbols needed by current development work.")
rule({"docker"}, 10e9, 3, "Review the disk image's current location and actual use in Docker Desktop > Settings > Resources > Advanced; a moved image may be outside Diskmap's measured default path. Review container logs in Docker Desktop, but Diskmap cannot measure their per-container allocation. Prune only data you identify as unused; volumes and the virtual disk may contain databases or personal work. Never move or delete the disk image directly in Finder.")
rule({"colima", "parallels"}, 10e9, 3, "Review unused environments in the owning tool. Virtual disks and volumes can contain databases and personal work.")
rule({"downloads"}, 2e9, 3, "Review downloaded installers and archives in Finder. Keep personal files and anything you cannot download again.")
rule({"archives"}, 5e9, 4, "Review old releases in Xcode Organizer. Archives and debug symbols may be irreplaceable; back them up before removing.")
rule({"device-backups"}, 10e9, 4, "In Finder, select the connected device and open General > Manage Backups. Review dates and device names; remove only backups you no longer need for a restore.")
rule({"adobe-media-cache"}, 1e9, 1, "Adobe shared media caches have accounted for tens or hundreds of gigabytes in user reports. Use Premiere Pro > Settings > Media Cache or After Effects > Settings > Disk; check connected source media before cleaning its cache database. Diskmap measures the default location only.")
rule({"adobe-caches"}, 1e9, 1, "After Effects disk caches have reached hundreds of gigabytes in user reports. Clear the active version in After Effects > Settings > Disk > Empty Disk Cache; cached frames rebuild, but each version has its own cache. Use each Adobe app's settings for its caches; custom folders outside this Adobe cache root are not measured.")
rule({"mail-logs"}, 100e6, 1, "Mail connection logs can grow very large when diagnostic logging is on. First turn off Window > Connection Doctor > Log Connection Activity, then inspect and remove logs with Show Logs. Preserve saved messages and local mailboxes.")
rule({"vscode-cache", "vscode-cached-data", "vscode-gpu-cache", "jetbrains"}, 1e9, 3, "Review generated editor data using the editor’s own storage controls. Preserve settings and recovery data.")
rule({"documentation", "documentation-assets"}, 500e6, 2, "Review offline reference downloads. Online documentation remains available; downloaded copies can be restored.")
rule({"codex-cache", "claude-cache", "cursor-cache", "cursor-cached-data", "cursor-gpu-cache"}, 500e6, 1, "Generated tool caches can be rebuilt. Quit the owning tool before reviewing this cache.")
rule({"codex-sessions", "codex-archives"}, 1e9, 2, "Session rollouts accumulate without bound, including completed subagent histories. Review old sessions in Codex and keep conversations you still need.")
rule({"opencode-snapshots"}, 1e9, 2, "Snapshot storage tracks working trees and can retain orphaned temporary packs after interrupted operations. Review snapshot contents in OpenCode; snapshots rebuild on next use.")
rule({"claude-projects", "claude-history"}, 1e9, 3, "Session transcripts and file-history checkpoints accumulate, and checkpoints can balloon during stuck sessions. Review old entries in Claude Code after moving durable notes elsewhere.")
return Rules
