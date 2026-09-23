--[[
  tests/reorder.test.lua — Tests for the reorder API

  Tests the Difference class and utilities for drag-to-reorder operations.
]]

local M = {}

local function equal(a, b, msg)
  if a == b then return true end
  error("FAIL: " .. (msg or "values not equal"))
end

local function arrayEqual(a, b, msg)
  if #a ~= #b then
    error("FAIL: array lengths differ (" .. #a .. " vs " .. #b .. "): " .. (msg or ""))
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      error("FAIL: array element " .. i .. " differs: " .. (msg or ""))
    end
  end
  return true
end

function M.run()
  local reorder = require("ui.reorder")
  local tests = 0
  local passed = 0

  -- Test 1: Difference creation
  tests = tests + 1
  local diff = reorder.Difference.new()
  if diff then passed = passed + 1 end

  -- Test 2: Move operation
  tests = tests + 1
  local items = { "a", "b", "c", "d", "e" }
  diff:move(5, 1)  -- Move "e" to front
  diff:apply(items)
  arrayEqual(items, { "e", "a", "b", "c", "d" }, "move to front")
  passed = passed + 1

  -- Test 3: Multiple moves
  tests = tests + 1
  items = { 1, 2, 3, 4, 5 }
  diff = reorder.Difference.new()
  diff:move(3, 1):move(5, 2)
  diff:apply(items)
  arrayEqual(items, { 3, 5, 1, 2, 4 }, "multiple moves")
  passed = passed + 1

  -- Test 4: Insert operation
  tests = tests + 1
  items = { "a", "b", "c" }
  diff = reorder.Difference.new()
  diff:insert(2, "x")
  diff:apply(items)
  arrayEqual(items, { "a", "x", "b", "c" }, "insert in middle")
  passed = passed + 1

  -- Test 5: Remove operation
  tests = tests + 1
  items = { "a", "b", "c", "d" }
  diff = reorder.Difference.new()
  diff:remove(2)
  diff:apply(items)
  arrayEqual(items, { "a", "c", "d" }, "remove item")
  passed = passed + 1

  -- Test 6: Mix of operations
  tests = tests + 1
  items = { 1, 2, 3, 4, 5 }
  diff = reorder.Difference.new()
  diff:move(5, 1):remove(2)
  diff:apply(items)
  arrayEqual(items, { 5, 2, 3, 4 }, "move then remove")
  passed = passed + 1

  -- Test 7: Non-mutating apply
  tests = tests + 1
  local original = { "a", "b", "c" }
  diff = reorder.Difference.new()
  diff:move(3, 1)
  local result = diff:applyTo(original)
  arrayEqual(original, { "a", "b", "c" }, "original unchanged")
  arrayEqual(result, { "c", "a", "b" }, "result has reorder")
  passed = passed + 1

  -- Test 8: isEmpty check
  tests = tests + 1
  diff = reorder.Difference.new()
  if diff:isEmpty() then passed = passed + 1 end

  -- Test 9: isEmpty after operations
  tests = tests + 1
  diff:move(1, 2)
  if not diff:isEmpty() then passed = passed + 1 end

  -- Test 10: Clear operations
  tests = tests + 1
  diff:clear()
  if diff:isEmpty() then passed = passed + 1 end

  -- Test 11: fromArrayDiff - simple move
  tests = tests + 1
  local old = { { _id = "a" }, { _id = "b" }, { _id = "c" } }
  local new = { { _id = "c" }, { _id = "a" }, { _id = "b" } }
  diff = reorder.fromArrayDiff(old, new, "_id")
  if #diff.operations >= 1 then passed = passed + 1 end

  -- Test 12: fromArrayDiff - insert detection
  tests = tests + 1
  old = { { _id = "1" }, { _id = "2" } }
  new = { { _id = "1" }, { _id = "x" }, { _id = "2" } }
  diff = reorder.fromArrayDiff(old, new, "_id")
  local hasInsert = false
  for _, op in ipairs(diff.operations) do
    if op.op == "insert" then hasInsert = true end
  end
  if hasInsert then passed = passed + 1 end

  -- Test 13: fromArrayDiff - remove detection
  tests = tests + 1
  old = { { _id = "1" }, { _id = "2" }, { _id = "3" } }
  new = { { _id = "1" }, { _id = "3" } }
  diff = reorder.fromArrayDiff(old, new, "_id")
  local hasRemove = false
  for _, op in ipairs(diff.operations) do
    if op.op == "remove" then hasRemove = true end
  end
  if hasRemove then passed = passed + 1 end

  -- Test 14: toTable serialization
  tests = tests + 1
  diff = reorder.Difference.new()
  diff:move(1, 2):insert(3, "item")
  local serialized = diff:toTable()
  if serialized.operations and #serialized.operations == 2 then
    passed = passed + 1
  end

  -- Test 15: Chaining
  tests = tests + 1
  items = { 1, 2, 3, 4 }
  local result = reorder.Difference.new()
    :move(4, 1)
    :move(3, 2)
    :applyTo(items)
  arrayEqual(result, { 4, 2, 1, 3 }, "chaining works")
  passed = passed + 1

	-- A single move shifts several indices; the generated script must still
	-- reproduce the exact target order when applied in sequence.
	tests = tests + 1
	old = { { _id = "a" }, { _id = "b" }, { _id = "c" } }
	new = { old[3], old[1], old[2] }
	diff = reorder.fromArrayDiff(old, new)
	local moved = diff:applyTo(old)
	equal(moved[1] == new[1] and moved[2] == new[2] and moved[3] == new[3],
		true, "generated move reproduces target order")
	passed = passed + 1

	tests = tests + 1
	old = { { _id = "a" }, { _id = "b" }, { _id = "c" }, { _id = "d" } }
	new = { old[4], { _id = "x" }, old[2] }
	diff = reorder.fromArrayDiff(old, new)
	local changed = diff:applyTo(old)
	equal(#changed == #new and changed[1] == new[1] and changed[2] == new[2]
		and changed[3] == new[3], true, "mixed generated edit script reproduces target")
	passed = passed + 1

	tests = tests + 1
	local unique = pcall(function()
		reorder.fromArrayDiff({ { _id = "a" }, { _id = "a" } }, new)
	end)
	if not unique then passed = passed + 1 end

  print(string.format("Reorder tests: %d/%d passed", passed, tests))
  return passed == tests
end

os.exit(M.run() and 0 or 1)
