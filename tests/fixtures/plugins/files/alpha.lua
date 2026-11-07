-- A single-file plugin: the manifest is the file's value.
return {
	api = 1,
	title = "Alpha",
	encode = function(host, value) return host.upper(value) end,
}
