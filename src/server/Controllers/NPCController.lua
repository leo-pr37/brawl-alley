-- ServerScriptService/NPCController.lua
-- Handles NPC initialization, state registration, and periodic updates.

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)
local StateMachine = require(game.ReplicatedStorage.Shared.StateMachine.StateMachine)
-- local StateConfig = require(game.ReplicatedStorage.StateMachine.Configs.NPCConfig)
local NPCFactory = require(game.ReplicatedStorage.Shared.StateMachine.Configs.NPCFactory) --allows custom npc states for various types


local NPCController = {}
local activeNPCs = {}

-- Reference to NPC folder (optional pattern)
local npcFolder = workspace:FindFirstChild("NPCs") or Instance.new("Folder", workspace)
npcFolder.Name = "NPCs"

---------------------------------------------------
-- NPC REGISTRATION
---------------------------------------------------
function NPCController.registerNPC(npc)
	if not npc or not npc:IsA("Model") then return end
	if activeNPCs[npc] then return end

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[NPCController] No humanoid found for", npc.Name)
		return
	end

	-- Create state machine for this NPC
	local NPCConfig = NPCFactory.get(npc)
	local sm = StateMachine.new(npc, NPCConfig)
	sm:changeState("Idle")

	-- Register globally
	StateManager.register(npc, sm)
	activeNPCs[npc] = sm

	print("[NPCController] Registered NPC:", npc.Name)

	-- Handle death / cleanup
	humanoid.Died:Connect(function()
		StateManager.unregister(npc)
		activeNPCs[npc] = nil
		task.delay(5, function()
			if npc and npc.Parent then npc:Destroy() end
		end)
	end)
end

---------------------------------------------------
-- NPC SPAWN HANDLING
---------------------------------------------------
-- Hook for dynamically spawned NPCs
function NPCController.onNPCSpawned(npc)
	NPCController.registerNPC(npc)
end

---------------------------------------------------
-- INITIALIZATION
---------------------------------------------------
function NPCController.init()
	-- Register existing NPCs already in workspace
	for _, npc in ipairs(npcFolder:GetChildren()) do
		NPCController.registerNPC(npc)
	end

	-- Automatically register any new NPCs parented into workspace.NPCs
	npcFolder.ChildAdded:Connect(function(child)
		task.wait(0.1) -- ensure model fully loaded
		NPCController.registerNPC(child)
	end)

	-- Update loop
	--game:GetService("RunService").Heartbeat:Connect(function(dt)
	--	NPCController.updateAll(dt)
	--end)

	print("[NPCController] Initialized and watching for NPCs.")
end

return NPCController