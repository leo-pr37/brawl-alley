-- ReplicatedStorage/StateMachine/States/NPC/Attack.lua

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)

local Attack = {}

Attack.Test = "Added Unique Tank Attack"

function Attack.Enter(entity)
	print(entity.Name, " entered Tank Attack")
end

function Attack.Update(entity, dt)
	-- could handle combo timing or attack cooldown logic here
end

function Attack.Exit(entity)
	-- optional cleanup, animation reset, etc.
end

return Attack

