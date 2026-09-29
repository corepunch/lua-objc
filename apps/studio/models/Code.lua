local Code = {}

local PREFIX = "demo/playground/"

local LUA = {
	matches = {
		{ pattern = "\\b(?:and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\\b", color = "keyword" },
		{ pattern = "\\b(?:math|string|table|utf8|coroutine|self|Model|Controller)\\b", color = "type" },
		{ pattern = "\\b[0-9]+(?:\\.[0-9]+)?\\b", color = "number" },
		{ pattern = "(?<=\\.)[A-Za-z_][A-Za-z0-9_]*", color = "property" },
		{ pattern = "\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", color = "function" },
		-- Later rules win when ranges overlap, so literals and comments keep
		-- their color even when they contain keyword-shaped words.
		{ pattern = "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|\\[\\[[\\s\\S]*?\\]\\]", color = "string" },
		{ pattern = "--\\[\\[[\\s\\S]*?\\]\\]", color = "comment" },
		{ pattern = "--[^\\n]*", color = "comment" },
	},
}

Code.rules = {
	colors = {
		plain = "label", keyword = "systemPurple", comment = "secondaryLabel",
		string = "systemRed", number = "systemBlue", type = "systemTeal",
		property = "systemOrange", ["function"] = "systemIndigo", tag = "systemTeal",
		attribute = "systemOrange", punctuation = "secondaryLabel",
	},
	languages = {
		lua = LUA,
		etlua = {
			matches = {
				{ pattern = "<!--[\\s\\S]*?-->", color = "comment" },
				{ pattern = "</?[A-Za-z][A-Za-z0-9:_-]*", color = "tag" },
				{ pattern = "\\b[A-Za-z_:][A-Za-z0-9_:.-]*(?=\\s*=)", color = "attribute" },
				{ pattern = "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'", color = "string" },
			},
			regions = {
				{ start = "<%-?=?", stop = "%>", rules = LUA, delimiter = "punctuation" },
			},
		},
	},
}

function Code.language(path)
	return path:match("%.etlua$") and "etlua" or "lua"
end

function Code.presentation(files, selected)
	local rows = {}
	for path in pairs(files) do
		local relative = path:sub(1, #PREFIX) == PREFIX and path:sub(#PREFIX + 1) or path
		local name, folder = relative:match("([^/]+)$"), relative:match("^(.+)/[^/]+$")
		table.insert(rows, {
			id = relative,
			name = name,
			folder = folder or "",
			display = folder and (folder .. "/" .. name) or name,
			icon = relative:match("%.etlua$") and "chevron.left.forwardslash.chevron.right" or "doc.text",
		})
	end
	table.sort(rows, function(left, right) return left.id < right.id end)
	if not selected or not files[PREFIX .. selected] then selected = rows[1] and rows[1].id end
	local source = selected and files[PREFIX .. selected] or ""
	return {
		files = rows,
		selected = selected,
		name = selected and selected:match("[^/]+$") or "No file selected",
		language = selected and Code.language(selected) or "lua",
		text = source,
	}
end

return Code
