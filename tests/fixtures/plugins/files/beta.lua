local SUFFIX = "-beta"
return {
	api = 1,
	title = "Beta",
	encode = function(_, value) return value .. SUFFIX end,
}
