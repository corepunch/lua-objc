-- SwiftUI's MeshGradient: a grid of coloured control points, drawn by
-- LuaMeshGradientView (src/shared/mesh_gradient.m) on AppKit and UIKit.
-- install() adds the constructor to a platform module.
local MeshGradient = {}

function MeshGradient.install(ns, bridge, applyLayout)
	--- Renders a native animated color mesh from a grid of control points.
	--- @prop width number required. Number of grid columns.
	--- @prop height number required. Number of grid rows.
	--- @prop points table optional. Normalized point coordinates in row-major order.
	--- @prop colors table optional. Colors in row-major order.
	--- @prop animated boolean optional. Animate interior points when true.
	--- @platform AppKit and UIKit.
	function ns.MeshGradient(props)
		props = props or {}
		local width, height = props.width or 3, props.height or 3
		local view = bridge._meshGradient(width, height)
		bridge._meshGradientConfigure(view, width, height, props.points, props.colors,
			props.animated == true)
		view.fillWidth, view.fillHeight = true, true
		return applyLayout(view, props)
	end
end

return MeshGradient
