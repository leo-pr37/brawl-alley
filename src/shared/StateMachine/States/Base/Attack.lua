-- ReplicatedStorage/StateMachine/States/NPC/Attack.lua
-- Base Attack

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)

local Attack = {}

function Attack.Enter(entity)
	print(entity.Name, " entered Base Attack")
	
	local sm = StateManager.getStateMachine(entity)
	if sm then sm:changeState("Idle") end
	
end

function Attack.Update(entity, dt)
	-- could handle combo timing or attack cooldown logic here
end

function Attack.Exit(entity)
	-- optional cleanup, animation reset, etc.
end

return Attack

