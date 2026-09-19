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
		self.regs[#self.regs + 1] = r
		return r
	end

	function Scope:dispose()
		for i = #self.regs, 1, -1 do
			local r = self.regs[i]
			self.regs[i] = nil
			if r ~= nil then
				r:dispose()
			end
		end
	end

	function Scope:close()
		Scope.drop(self)
		self:dispose()
	end

	Scope.__close = Scope.close

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
