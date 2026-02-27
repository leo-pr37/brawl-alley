local NPCSpawner = {}

local ServerStorage = game:GetService("ServerStorage")
local npcToSpawn = ServerStorage.NPCs:FindFirstChild("Villager") -- Change "Villager" to your NPC's name

local spawnPart = workspace:FindFirstChild("NPCSpawnPart") -- Change "SpawnPart" to your part's name


-- Handles creation, respawn, and cleanup of enemies.
function NPCSpawner.init()

	-- Check if everything exists before proceeding
	if not npcToSpawn then
		warn("NPC model not found in ServerStorage!")
		return
	end
	if not spawnPart then
		warn("SpawnPart not found in Workspace!")
		return
	end

	local function spawnNPC()
		local newNpc = npcToSpawn:Clone()

		-- Ensure controller is notified before parenting so any setup can run
		require(game.ServerScriptService.Server.Controllers.NPCController).onNPCSpawned(newNpc)

		-- Try to ensure the model has a PrimaryPart. Typical convention: HumanoidRootPart
		local primary = newNpc:FindFirstChild("HumanoidRootPart") or newNpc:FindFirstChildWhichIsA("BasePart")
		if primary then
			newNpc.PrimaryPart = primary
		end

		newNpc.Parent = workspace.NPCs

		-- Prefer SetPrimaryPartCFrame when PrimaryPart is set; otherwise use PivotTo if available
		if newNpc.PrimaryPart then
			newNpc:SetPrimaryPartCFrame(spawnPart.CFrame)
		elseif newNpc.PivotTo then
			-- PivotTo doesn't require PrimaryPart and is a safer modern API
			newNpc:PivotTo(spawnPart.CFrame)
		else
			warn("[NPCSpawner] NPC has no PrimaryPart and PivotTo is unavailable; cannot position model")
		end

		return newNpc
	end

	local respawnTime = 2 -- Time in seconds before respawning

	task.spawn(function()
		while true do
			local currentNpc = spawnNPC()

			-- Check if the NPC's Humanoid exists and connect to its Died event
			local humanoid = currentNpc:WaitForChild("Humanoid")
			if humanoid then
				humanoid.Died:Wait()
			end

			-- The NPC has died, wait for the respawn timer
			task.wait(respawnTime)
		end
	end)
	print("NPC Spawner Initialized")
end
	



return NPCSpawner
