-- The Settings tab: the reading options (a coordinating controller owns
-- them, they are shared with the in-book sheet) and the guide.
return {
	settings = {
		view = "pages/Settings",
		data = function() return {} end,
		howToPlay = function(self) self.app.openGuide() end,
		queries = { howToPlay = true },
		rendered = function(self, refs) self.app.mountReadingOptions(refs.readingOptions) end,
	},
}
