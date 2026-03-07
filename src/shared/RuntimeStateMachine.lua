--[[
	StateMachine (Shared)
	Lightweight state machine for players and enemies.
	Each state has: enter(model, prevState, ...), exit(model, nextState),
	update(model, dt) callbacks and optional lock duration.
]]

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(owner, stateDefinitions)
	local self = setmetatable({}, StateMachine)
	self._owner = owner         -- Model or character reference
	self._states = stateDefinitions or {}
	self._current = nil         -- current state name
	self._lockUntil = 0         -- tick() value until which transitions are blocked
	self._data = {}             -- arbitrary per-instance data (combo step, etc.)
	return self
end

function StateMachine:GetState()
	return self._current
end

function StateMachine:GetData(key)
	return self._data[key]
end

function StateMachine:SetData(key, value)
	self._data[key] = value
end

function StateMachine:IsLocked()
	return tick() < self._lockUntil
end

function StateMachine:Lock(duration)
	self._lockUntil = tick() + (duration or 0)
end

function StateMachine:Unlock()
	self._lockUntil = 0
end

function StateMachine:CanTransition(newState)
	if self._current == newState then return false end
	if self:IsLocked() then return false end
	local def = self._states[newState]
	if not def then return false end
	-- Check if current state allows exit
	local curDef = self._states[self._current]
	if curDef and curDef.canExit then
		if not curDef.canExit(self._owner, newState) then
			return false
		end
	end
	-- Check if new state allows entry from current
	if def.canEnter then
		if not def.canEnter(self._owner, self._current) then
			return false
		end
	end
	return true
end

-- Transition to a new state. force=true bypasses lock and gate checks.
function StateMachine:SetState(newState, force, ...)
	if not force and not self:CanTransition(newState) then
		return false
	end

	local prevState = self._current
	local prevDef = self._states[prevState]
	local newDef = self._states[newState]

	if not newDef then
		warn("[StateMachine] Unknown state: " .. tostring(newState))
		return false
	end

	-- Exit previous state
	if prevDef and prevDef.exit then
		prevDef.exit(self._owner, newState, self)
	end

	self._current = newState
	self._lockUntil = 0

	-- Enter new state
	if newDef.enter then
		newDef.enter(self._owner, prevState, self, ...)
	end

	-- Auto-lock if state defines a lock duration
	if newDef.lockDuration then
		local dur = newDef.lockDuration
		if type(dur) == "function" then
			dur = dur(self._owner, self)
		end
		self:Lock(dur)
	end

	return true
end

-- Call the current state's update. Returns nothing.
function StateMachine:Update(dt)
	local def = self._states[self._current]
	if def and def.update then
		def.update(self._owner, dt, self)
	end
end

-- Force-transition to Dead (always succeeds)
function StateMachine:Kill()
	if self._states.Dead then
		self:SetState("Dead", true)
	end
end

return StateMachine
