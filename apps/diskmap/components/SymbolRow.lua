local SYMBOL = {column = 26, gap = 10}
return {props = {name = "str", color = {type = "str", default = "secondary"}, size = {type = "num", default = 18}},
	data = function() return {symbol = SYMBOL} end}
