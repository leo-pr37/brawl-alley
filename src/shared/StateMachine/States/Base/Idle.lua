-- ReplicatedStorage/StateMachine/States/Idle.lua

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)
local Players = game:GetService("Players") -- Get the Players service

local Idle = {}

function Idle.Enter(entity)
	local hum = entity:FindFirstChildOfClass("Humanoid")
	if hum then hum:Move(Vector3.zero) end
end

function Idle.Update(entity, dt)
	local hum = entity:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	
	-- Prevent Player Characters from running NPC logic
	if Players:GetPlayerFromCharacter(entity) then
		-- This is a Player character. It should NOT automatically start chasing.
		-- We return here to skip the rest of the target-finding and state-change logic.
		return 
	end

	-- NPC CHASE START LOGIC (NEED TO MOVE THIS TO NPC Idle state file)
	local root = entity:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local nearest, dist = nil, math.huge
	for _, player in ipairs(game.Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local diff = player.Character.HumanoidRootPart.Position - root.Position
			local mag = diff.Magnitude
			if mag < dist then
				nearest, dist = player.Character, mag
			end
		end
	end

	if nearest and dist < 40 then
		local sm = StateManager.getStateMachine(entity)
		if sm then sm:changeState("Chase") end
	end
end

function Idle.Exit(entity)
	-- nothing special yet
end

return Idle

