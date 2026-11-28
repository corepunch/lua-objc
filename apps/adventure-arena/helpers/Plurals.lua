-- Counted nouns in every language, in one place. A language's resources
-- declare `pluralRule` (a rule below) and one string per form the rule
-- distinguishes, named `<noun>_<form>`: moveCount_one, moveCount_few ...
-- Pure: the app's resources in the language being read come in as `strings`.
local Plurals = {}

-- Each rule names the forms it uses and picks one for a whole number.
local RULES = {
	-- English and German: 1 is singular, everything else plural.
	oneOther = {
		forms = { "one", "other" },
		form = function(n) return n == 1 and "one" or "other" end,
	},
	-- Russian: 1, 21, 101 (but not 11) take the first form; 2-4, 22-24
	-- (but not 12-14) the second; the rest, 0 and 11-14 included, the third.
	eastSlavic = {
		forms = { "one", "few", "many" },
		form = function(n)
			local units, tens = n % 10, n % 100
			if units == 1 and tens ~= 11 then return "one" end
			if units >= 2 and units <= 4 and (tens < 12 or tens > 14) then return "few" end
			return "many"
		end,
	},
}

-- The forms a rule distinguishes, for tests and for authors of a language.
function Plurals.forms(rule)
	return (RULES[rule] or error("no plural rule " .. tostring(rule))).forms
end

-- The form of `count` ("one", "few" ...) under the strings' rule.
function Plurals.form(strings, count)
	local rule = RULES[strings.pluralRule] or error("no plural rule " .. tostring(strings.pluralRule))
	return rule.form(math.abs(math.floor(tonumber(count) or 0)))
end

-- "5 moves": the `noun` string of the count's form, with the count in it.
function Plurals.format(strings, noun, count)
	count = math.floor(tonumber(count) or 0)
	local id = noun .. "_" .. Plurals.form(strings, count)
	return string.format(strings[id] or error("missing string " .. id), count)
end

return Plurals
