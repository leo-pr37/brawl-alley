local statesFolder = script.Parent.Parent.States
--local Utility = require(script.Parent.Utility)

local PlayerConfig = {}

-- 1. Load Base States (e.g., Idle, Attack)
local BaseStates = statesFolder.Base
for _, module in pairs(BaseStates:GetChildren()) do
	if module:IsA("ModuleScript") then
		PlayerConfig[module.Name] = require(module)
	end
end

-- 2. Load Player-Specific States (e.g., Dodge, Block)
local PlayerStates = statesFolder.Player
for _, module in pairs(PlayerStates:GetChildren()) do
	if module:IsA("ModuleScript") then
		-- This will overwrite Base states if names conflict, which is desired.
		PlayerConfig[module.Name] = require(module)
	end
end

return PlayerConfig