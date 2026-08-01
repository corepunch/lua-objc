-- Minimal preview example.
-- Run with:  ./lua-objc --preview [--width=400] [--height=300] [--out=out.png] examples/preview/init.lua

local Controller = require("examples.preview.Controller")
return Controller.new():render()
