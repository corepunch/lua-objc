-- Product review thresholds, not claims about normal size or guaranteed reclaimable space.
-- Rule IDs map to catalog ownership; no rule grants additional deletion authority.
local Rules = {}
local function rule(ids, threshold, priority, advice)
	for _, id in ipairs(ids) do Rules[id] = {threshold = threshold, priority = priority, advice = advice} end
end
rule({"derived"}, 1e9, 1, "Build products and indexes can be regenerated. Quit Xcode before reviewing this cache.")
rule({"npm", "pip", "brew"}, 500e6, 1, "Downloaded packages can be fetched again. Review this cache after closing the owning package manager.")
rule({"simulators"}, 5e9, 2, "Review unused simulator devices. Removing a device also removes its installed test apps and data.")
rule({"devices"}, 2e9, 2, "Review support files for devices you still debug. Keep symbols needed by current development work.")
rule({"docker", "colima", "parallels"}, 10e9, 3, "Review unused environments in the owning tool. Virtual disks and volumes can contain databases and personal work.")
rule({"downloads"}, 2e9, 3, "Review downloaded installers and archives in Finder. Keep personal files and anything you cannot download again.")
rule({"archives"}, 5e9, 4, "Review old releases in Xcode Organizer. Archives and debug symbols may be irreplaceable; back them up first.")
rule({"device-backups"}, 10e9, 4, "Review old device backups in Finder. Keep the restore points you still need.")
rule({"vscode-cache", "vscode-cached-data", "vscode-gpu-cache", "jetbrains"}, 1e9, 3, "Review generated editor data using the editor’s own storage controls. Preserve settings and recovery data.")
rule({"documentation", "documentation-assets"}, 500e6, 2, "Review offline reference downloads. Online documentation remains available; downloaded copies can be restored.")
rule({"codex-cache", "claude-cache", "cursor-cache", "cursor-cached-data", "cursor-gpu-cache"}, 500e6, 1, "Generated tool caches can be rebuilt. Quit the owning tool before reviewing this cache.")
rule({"codex-sessions", "codex-archives"}, 1e9, 2, "Session rollouts accumulate without bound, including completed subagent histories. Review old sessions in Codex and keep conversations you still need.")
rule({"opencode-snapshots"}, 1e9, 2, "Snapshot storage tracks working trees and can retain orphaned temporary packs after interrupted operations. Review snapshot contents in OpenCode; snapshots rebuild on next use.")
rule({"claude-projects", "claude-history"}, 1e9, 3, "Session transcripts and file-history checkpoints accumulate, and checkpoints can balloon during stuck sessions. Review old entries in Claude Code after moving durable notes elsewhere.")
return Rules
