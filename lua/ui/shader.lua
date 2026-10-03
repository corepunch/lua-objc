-- ShaderView: a Metal picture drawn every display frame
-- (src/appkit/shader_view.m), macOS only. install() adds the constructor to
-- the AppKit module.
local Shader = {}

local function readShader(path)
	local file = assert(io.open(path, "r"), "ShaderView: cannot read " .. tostring(path))
	local text = file:read("a")
	file:close()
	return text
end

function Shader.install(ns, bridge, applyLayout)
	--- Draws a Metal fragment shader every display frame, like SwiftUI's
	--- `TimelineView(.animation)` around a `ShaderLibrary` color effect.
	--- The source defines `fragment float4 name(ShaderVertex in [[stage_in]],
	--- constant ShaderInputs &inputs [[buffer(0)]])`; `inputs` carries `size`
	--- (pixels), `time` (seconds), `count` and `values[256]`. Assign `values`
	--- from Lua to animate it. The view is transparent where the shader is.
	--- A program can instead be linked from `sources`, `{path = …}` files and
	--- `{code = …}` snippets compiled in order as one translation unit, so a
	--- shared library, plugin-contributed functions and an entry point can live
	--- in separate files. Each chunk opens with a `#line` directive, so compiler
	--- errors name the file and line they came from.
	---
	--- Meshes: with `layers`, the view first renders `draws` into that many
	--- offscreen HDR layers (RGBA16Float, cleared to transparent black, with a
	--- depth buffer), and `function` finishes the picture from them: layer i is
	--- `texture2d<float> [[texture(i - 1)]]`, mipmapped every frame so coarse
	--- levels serve as wide blurs. Each draw is a table:
	--- `vertex`, `fragment` (function names), `count` (vertices), `instances`
	--- (1), `layer` (1), `primitive` (`triangle`, `triangleStrip`, `line`,
	--- `lineStrip`, `point`), `blend` (`opaque`, `alpha` premultiplied, `add`),
	--- `depth` (`none`, `test`, `write`), `cull` (`none`, `back`, `front`),
	--- `data` (floats at `const device float *data [[buffer(1)]]`) and `params`
	--- (up to 64 floats at `constant float *params [[buffer(2)]]`). Both stages
	--- get `inputs` at buffer(0). Vertices usually come from `vertex_id` and
	--- `instance_id`; `fullscreenVertex` covers the view with `ShaderVertex`.
	--- Assigning `draws` compiles their pipelines, and a bad list raises
	--- without replacing the running one.
	--- @prop source string optional. Path of a `.metal` file with the fragment function.
	--- @prop sources table optional. `<ShaderSource path="…">` / `<ShaderSource code="…">` chunks, in order.
	--- @prop function string required. Fragment function name; with layers, the finishing pass.
	--- @prop values table optional. Initial floats for `inputs.values`.
	--- @prop layers number optional. Offscreen layers the draws render into, 0…4 (0).
	--- @prop draws table optional. Mesh passes, in order (see above).
	--- @prop onClick function optional. `onClick(view, x, y)` in the view's top-left points.
	--- @prop onScroll function optional. `onScroll(view, dx, dy)` in points, the user's scrolling direction applied.
	--- @platform AppKit.
	function ns.ShaderView(props)
		props = props or {}
		local text
		if props.sources then
			assert(props.source == nil, "ShaderView takes source or sources, not both")
			local chunks = {}
			for index, chunk in ipairs(props.sources) do
				assert((chunk.path == nil) ~= (chunk.code == nil), "ShaderSource requires exactly one of path or code")
				local name = chunk.path or ("code " .. index)
				table.insert(chunks, string.format('#line 1 "%s"\n%s\n', name, chunk.path and readShader(chunk.path) or chunk.code))
			end
			assert(#chunks > 0, "ShaderView sources is empty")
			text = table.concat(chunks)
		else
			text = readShader(assert(props.source, "ShaderView requires source or sources"))
		end
		local view = bridge._shaderView(text, assert(props["function"], "ShaderView requires function"),
			props.onClick, props.onScroll)
		if props.values then view.values = props.values end
		if props.layers then view.layers = props.layers end
		if props.draws then view.draws = props.draws end
		-- Like a gradient, a shader has no intrinsic size and fills its proposal.
		view.fillWidth, view.fillHeight = true, true
		-- The view reports its own clicks with their point; the generic
		-- click gesture would report none.
		local layout = {}
		for key, value in pairs(props) do
			if key ~= "onClick" and key ~= "onScroll" then layout[key] = value end
		end
		return applyLayout(view, layout)
	end
end

return Shader
