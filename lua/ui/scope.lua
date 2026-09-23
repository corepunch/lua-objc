--[[
  ui/scope.lua — Lua-side registration set for native LuaReg objects.

  Every on*, timer, watcher, and HTTP callback created while a Scope is
  current is added to it. Window close or an explicit dispose unrefs those
  captures so the Lua/ARC cycle cannot keep a screen alive.
]]

return function(bridge)
	local Scope = {}
	Scope.__index = Scope

	local current = nil

	function Scope.new()
		return setmetatable({ regs = {} }, Scope)
	end

	function Scope:add(r)
		if r == nil then return r end
		-- Prune entries whose native registration was already disposed
		-- (fired timers, replaced callbacks) so the list does not grow
		-- for the window's lifetime.
		for i = #self.regs, 1, -1 do
			local existing = self.regs[i]
			local ok, dead = pcall(function()
				return existing ~= nil and existing:isDisposed()
			end)
			if ok and dead then
				table.remove(self.regs, i)
			end
		end
		table.insert(self.regs, r)
		return r
	end

	function Scope:dispose()
		if self.closed then return end
		self.closed = true
		for i = #self.regs, 1, -1 do
			local r = self.regs[i]
			self.regs[i] = nil
			if r ~= nil then
				r:dispose()
			end
		end
	end

	function Scope:close()
		if self.closed then
			Scope.drop(self)
			return
		end
		Scope.drop(self)
		self:dispose()
	end

	Scope.__close = Scope.close

	-- Run fn with scope as the current scope, restoring the previous one.
	-- Used by tests and by per-screen navigation scopes.
	function Scope.withScope(scope, fn, ...)
		assert(scope ~= nil, "withScope requires a scope")
		assert(type(fn) == "function", "withScope requires a function")
		local prev = current
		current = scope
		bridge._setCurrentScope(scope)
		local results = table.pack(pcall(fn, ...))
		current = prev
		bridge._setCurrentScope(prev)
		if not results[1] then
			error(results[2], 2)
		end
		return table.unpack(results, 2, results.n)
	end

	function Scope.current()
		return current
	end

	function Scope.push()
		local s = Scope.new()
		s._prev = current
		current = s
		bridge._setCurrentScope(s)
		return s
	end

	function Scope.pop()
		local s = current
		if not s then return nil end
		current = s._prev
		s._prev = nil
		bridge._setCurrentScope(current)
		return s
	end

	function Scope.drop(scope)
		if not scope then return end
		if current == scope then
			Scope.pop()
			return
		end
		local s = current
		while s do
			if s._prev == scope then
				s._prev = scope._prev
				break
			end
			s = s._prev
		end
		scope._prev = nil
	end

	return Scope
end
