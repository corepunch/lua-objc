-- The races in play order. A new race is a data file in catalog/tracks/
-- and one line here. (Each require is in parentheses: require returns a
-- second value that would otherwise join the list.)
return {
	(require("demo.playground.catalog.tracks.oval")),
	(require("demo.playground.catalog.tracks.hairpin")),
	(require("demo.playground.catalog.tracks.grandprix")),
}
