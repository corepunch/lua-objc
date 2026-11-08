-- The levels in play order. A new level is a data file in catalog/levels/
-- and one line here. (Each require is in parentheses: require returns a
-- second value that would otherwise join the list.)
return {
	(require("demo.playground.catalog.levels.meadow")),
	(require("demo.playground.catalog.levels.hills")),
	(require("demo.playground.catalog.levels.peak")),
}
