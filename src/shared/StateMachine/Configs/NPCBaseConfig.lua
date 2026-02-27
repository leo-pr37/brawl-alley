local statesFolder = script.Parent.Parent.States
--local Utility = require(script.Parent.Utility)

local NPCBaseConfig = {}

-- 1. Load Base States (e.g., Idle, Attack)
local BaseStates = statesFolder.Base
for _, module in pairs(BaseStates:GetChildren()) do
	if module:IsA("ModuleScript") then
		NPCBaseConfig[module.Name] = require(module)
	end
end

-- 2. Load Generic NPC States (e.g., Chase, Flee)
local NPCStates = statesFolder.NPC
for _, module in pairs(NPCStates:GetChildren()) do
	if module:IsA("ModuleScript") then
		NPCBaseConfig[module.Name] = require(module)
	end
end

return NPCBaseConfig