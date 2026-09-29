-- A second module for a bundled tag; tests/components.test.lua expects the
-- renderer to refuse it rather than substitute one chart for the other.
return { build = function(self, ns) return ns.VStack {} end }
