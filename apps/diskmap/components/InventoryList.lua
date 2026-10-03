local COLUMNS = {name = 180, role = 110, roleMinimum = 90, date = 150, size = 110, sizeMinimum = 100}
return {props = {kind = {type = "str", default = "devices"}}, data = function(props)
	local worktree, runtime, plan = props.kind == "worktrees", props.kind == "runtimes", props.kind == "plan"
	return {columns = COLUMNS, nameTitle = worktree and "Worktree" or runtime and "Runtime" or "Device",
		subtitle = plan and "reason" or (worktree or runtime) and "subtitle" or "runtime",
		role = (worktree or plan) and "roleLabel" or runtime and "deviceText" or "state",
		roleTitle = (worktree or plan) and "Plan" or runtime and "Devices" or "State",
		dateTitle = worktree and "Last change" or "Last used", sizeTitle = (worktree or runtime) and "On disk" or "Apps & data"}
end}
