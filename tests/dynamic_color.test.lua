_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- "light|dark" colour pairs, like an asset-catalog colour with a Dark variant.
local paper = ns.Color("#FAF7F0|#161618")
t.expect(paper ~= nil, "a light|dark pair resolves to a colour")
t.expect(paper.type == 2 or tostring(paper):find("NSDynamic", 1, true) or paper.className:find("Dynamic", 1, true) ~= nil,
	"a pair is a dynamic colour that resolves per appearance")
t.expect(ns.Color("systemIndigo|systemTeal") ~= nil, "pairs accept semantic names")
local src = assert(io.open("src/uikit/views.m", "r")):read("*a")
t.expect(src:find("colorWithDynamicProvider", 1, true) ~= nil, "UIKit resolves pairs with the trait collection")
