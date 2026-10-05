-- One width for every page: a label and its value stay within one glance,
-- and moving between pages never moves where content starts.
local FRAME = {width = 960, margin = 24}
return {props = {scrolls = {type = "bool", default = true}}, data = function() return {frame = FRAME} end}
