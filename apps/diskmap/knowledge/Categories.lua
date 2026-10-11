-- The pages of the sidebar: the sources developers lose space to
-- (VISION.md). Each is one list of measured items, drawn by the `category`
-- route. `summary` leads the page; `empty` is said when nothing of the kind
-- is on this Mac.
return {
	{id = "xcode", title = "Xcode", icon = "hammer.fill", color = "systemBlue", key = "3",
		summary = "DerivedData per project, device support per OS version, archives and caches.",
		empty = "No Xcode data was found in ~/Library/Developer."},
	{id = "simulators", title = "Simulators", icon = "iphone", color = "systemIndigo", key = "4",
		summary = "Simulator devices and the runtimes they run on, from simctl.",
		empty = "No simulator devices or runtimes were found."},
	{id = "projects", title = "Projects", icon = "shippingbox.fill", color = "systemOrange", key = "5",
		summary = "Build output beside your projects: node_modules, target, .build and the like.",
		empty = "No build folders were found in your project folders."},
	{id = "worktrees", title = "Worktrees", icon = "arrow.triangle.branch", color = "systemPurple", key = "6",
		summary = "Linked Git worktrees, with whether their work is merged, published or still in progress.",
		empty = "No linked worktrees were found in your repositories."},
	{id = "packages", title = "Packages", icon = "cube.box.fill", color = "systemTeal", key = "7",
		summary = "Downloaded packages that a lockfile restores, and installed toolchains.",
		empty = "No package caches were found."},
	{id = "editors", title = "Editors", icon = "chevron.left.forwardslash.chevron.right", color = "systemGreen", key = "8",
		summary = "Caches editors rebuild, and the extensions they installed.",
		empty = "No editor caches were found."},
	{id = "ai", title = "AI Tools", icon = "sparkles", color = "systemPink", key = "9",
		summary = "Codex, Claude, OpenCode and Grok: transcripts you decide about, caches that rebuild, and downloaded models.",
		empty = "No AI tool data was found."},
	{id = "system", title = "System Data", icon = "gearshape.2.fill", color = "systemGray", key = "0",
		summary = "What macOS Storage calls System Data, taken apart: volumes, downloaded assets, caches, logs and temporary files.",
		empty = "System Data could not be measured."},
}
