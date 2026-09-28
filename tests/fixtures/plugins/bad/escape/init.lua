-- Reaching for the loader or the file system fails: they are not there.
return {api = 1, title = "Escape", create = function() end, found = {
	require = require, io = io, os = os, load = load, debug = debug, package = package, dofile = dofile,
}}
