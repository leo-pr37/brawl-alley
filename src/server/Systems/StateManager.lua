-- ServerScriptService/StateManager.lua
-- Central registry for all state machines (players + NPCs)

local StateManager = {}
local entityStateMachines = {}

function StateManager.init() end

function StateManager.register(entity, stateMachine)
	if not entity or not stateMachine then return end
	entityStateMachines[entity] = stateMachine
	print("[StateManager] Registered:", entity.Name)
	print(entityStateMachines)
end

function StateManager.unregister(entity)
	if entityStateMachines[entity] then
		entityStateMachines[entity] = nil
		print("[StateManager] Unregistered:", entity.Name)
	end
end

function StateManager.getStateMachine(entity)
	return entityStateMachines[entity]
end

function StateManager.updateAll(dt)
	-- Iterate over every single state machine registered
	for entity, sm in pairs(entityStateMachines) do
		-- Perform a check to ensure the entity is still valid
		if entity and entity.Parent and entity:FindFirstChildOfClass("Humanoid") then
			sm:update(dt)
			sm:tickCooldowns(dt)
		else
			-- Clean up invalid or destroyed entities
			StateManager.unregister(entity)
		end
	end
end

-- Optional helper for auto-creating a machine if missing
function StateManager.ensure(entity, StateConfig)
	local sm = StateManager.getStateMachine(entity)
	if not sm then
		local BaseStateMachine = require(game.ReplicatedStorage.StateMachine.StateMachine)
		sm = BaseStateMachine.new(entity, StateConfig)
		StateManager.register(entity, sm)
		sm:changeState("Idle")
	end
	return sm
end

return StateManager
