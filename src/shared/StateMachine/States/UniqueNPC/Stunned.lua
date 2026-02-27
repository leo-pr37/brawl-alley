-- ReplicatedStorage/StateMachine/States/NPC/Stunned.lua

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)

local Stunned = {}

Stunned.Test = "Added Unique Tank Stunned"

function Stunned.Enter(entity)
	print(entity.Name, " entered Tank Stunned")
end

function Stunned.Update(entity, dt)
	-- could handle combo timing or Stunned cooldown logic here
end

function Stunned.Exit(entity)
	-- optional cleanup, animation reset, etc.
end

return Stunned

