-- ReplicatedStorage/StateMachine/States/Chase.lua

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)

local Chase = {}

function Chase.Enter(entity)
	print(entity.Name, "entered Chase")
end

function Chase.Update(entity, dt)
	local hum = entity:FindFirstChildOfClass("Humanoid")
	local root = entity:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end

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

	if not nearest then
		local sm = StateManager.getStateMachine(entity)
		if sm then sm:changeState("Idle") end
		return
	end

	if dist > 20 then
		local sm = StateManager.getStateMachine(entity)
		if sm then sm:changeState("Idle") end
	elseif dist < 10 then
		local sm = StateManager.getStateMachine(entity)
		if sm then sm:changeState("Attack") end
	else
		hum:MoveTo(nearest.HumanoidRootPart.Position)
	end
end

function Chase.Exit(entity)
	-- stop movement if leaving chase
	local hum = entity:FindFirstChildOfClass("Humanoid")
	if hum then hum:Move(Vector3.zero) end
end

return Chase
