local LEGEND = {row = 18, name = 92, size = 84, share = 40, column = 20, gap = 6}
return {props = {label = "str", color = "str", sizeText = "str", share = "str", linked = "bool", action = "str", column = "num", gap = "num"},
	data = function(props) return {legend = LEGEND, symbolColumn = props.column or LEGEND.column, symbolGap = props.gap or LEGEND.gap} end}
