--[[
	GameManager (Server)
	Manages the overall game state: lobby, waves, game over, restart.
	Handles enemy spawning, damage processing, and score tracking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local EnemyTypes = require(Shared:WaitForChild("EnemyTypes"))
local Utils = require(Shared:WaitForChild("Utils"))

-- Create RemoteEvents for client-server communication
local function createRemote(className, name)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local DamageEvent = createRemote("RemoteEvent", "DamageEvent")
local AttackEvent = createRemote("RemoteEvent", "AttackEvent")
local GameStateEvent = createRemote("RemoteEvent", "GameStateEvent")
local ScoreEvent = createRemote("RemoteEvent", "ScoreEvent")
local EnemyHitEvent = createRemote("RemoteEvent", "EnemyHitEvent")
local PlayerDiedEvent = createRemote("RemoteEvent", "PlayerDiedEvent")
local RequestRestartEvent = createRemote("RemoteEvent", "RequestRestartEvent")
local SpawnEffectEvent = createRemote("RemoteEvent", "SpawnEffectEvent")

-- Game state
local gameState = "Lobby" -- Lobby, Playing, GameOver
local currentWave = 0
local enemiesAlive = 0
local totalScore = 0 -- shared score for co-op
local playerScores = {} -- per-player scores
local playerDeaths = {} -- track dead players

-- Folders
local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"
enemiesFolder.Parent = workspace

local arenaFolder = Instance.new("Folder")
arenaFolder.Name = "Arena"
arenaFolder.Parent = workspace

-- Arena dimensions
local ARENA_WIDTH = 80
local ARENA_DEPTH = 50
local ARENA_CENTER = Vector3.new(0, 0, 0)

------------------------------------------------------------
-- ARENA BUILDING
------------------------------------------------------------
local function buildArena()
	-- Clear old arena
	arenaFolder:ClearAllChildren()

	-- Ground
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(ARENA_WIDTH + 20, 1, ARENA_DEPTH + 20)
	ground.Position = Vector3.new(0, -0.5, 0)
	ground.Anchored = true
	ground.BrickColor = BrickColor.new("Dark stone grey")
	ground.Material = Enum.Material.Concrete
	ground.Parent = arenaFolder

	-- Street lines
	for i = -ARENA_WIDTH/2, ARENA_WIDTH/2, 10 do
		local line = Instance.new("Part")
		line.Name = "StreetLine"
		line.Size = Vector3.new(1, 0.05, 4)
		line.Position = Vector3.new(i, 0.03, 0)
		line.Anchored = true
		line.BrickColor = BrickColor.new("Institutional white")
		line.Material = Enum.Material.SmoothPlastic
		line.Parent = arenaFolder
	end

	-- Walls
	local wallHeight = 12
	local wallThickness = 3

	-- Back wall
	local backWall = Instance.new("Part")
	backWall.Name = "BackWall"
	backWall.Size = Vector3.new(ARENA_WIDTH + 20, wallHeight, wallThickness)
	backWall.Position = Vector3.new(0, wallHeight/2, -ARENA_DEPTH/2 - wallThickness/2)
	backWall.Anchored = true
	backWall.BrickColor = BrickColor.new("Dark taupe")
	backWall.Material = Enum.Material.Brick
	backWall.Parent = arenaFolder

	-- Front wall (lower, like a curb/barrier)
	local frontWall = Instance.new("Part")
	frontWall.Name = "FrontWall"
	frontWall.Size = Vector3.new(ARENA_WIDTH + 20, wallHeight, wallThickness)
	frontWall.Position = Vector3.new(0, wallHeight/2, ARENA_DEPTH/2 + wallThickness/2)
	frontWall.Anchored = true
	frontWall.BrickColor = BrickColor.new("Dark taupe")
	frontWall.Material = Enum.Material.Brick
	frontWall.Parent = arenaFolder

	-- Left wall
	local leftWall = Instance.new("Part")
	leftWall.Name = "LeftWall"
	leftWall.Size = Vector3.new(wallThickness, wallHeight, ARENA_DEPTH + 20)
	leftWall.Position = Vector3.new(-ARENA_WIDTH/2 - wallThickness/2, wallHeight/2, 0)
	leftWall.Anchored = true
	leftWall.BrickColor = BrickColor.new("Reddish brown")
	leftWall.Material = Enum.Material.Brick
	leftWall.Parent = arenaFolder

	-- Right wall
	local rightWall = Instance.new("Part")
	rightWall.Name = "RightWall"
	rightWall.Size = Vector3.new(wallThickness, wallHeight, ARENA_DEPTH + 20)
	rightWall.Position = Vector3.new(ARENA_WIDTH/2 + wallThickness/2, wallHeight/2, 0)
	rightWall.Anchored = true
	rightWall.BrickColor = BrickColor.new("Reddish brown")
	rightWall.Material = Enum.Material.Brick
	rightWall.Parent = arenaFolder

	-- Props: dumpsters, barrels, crates
	local props = {
		{Name="Dumpster", Size=Vector3.new(4, 3, 3), Pos=Vector3.new(-25, 1.5, -18), Color="Earth green", Mat=Enum.Material.Metal},
		{Name="Dumpster2", Size=Vector3.new(4, 3, 3), Pos=Vector3.new(30, 1.5, 20), Color="Earth green", Mat=Enum.Material.Metal},
		{Name="Barrel1", Size=Vector3.new(2, 3, 2), Pos=Vector3.new(-15, 1.5, -20), Color="Brown", Mat=Enum.Material.Wood},
		{Name="Barrel2", Size=Vector3.new(2, 3, 2), Pos=Vector3.new(-13, 1.5, -20), Color="Brown", Mat=Enum.Material.Wood},
		{Name="Barrel3", Size=Vector3.new(2, 3, 2), Pos=Vector3.new(20, 1.5, 18), Color="Brown", Mat=Enum.Material.Wood},
		{Name="Crate1", Size=Vector3.new(3, 3, 3), Pos=Vector3.new(10, 1.5, -22), Color="Brick yellow", Mat=Enum.Material.Wood},
		{Name="Crate2", Size=Vector3.new(3, 3, 3), Pos=Vector3.new(13, 1.5, -22), Color="Brick yellow", Mat=Enum.Material.Wood},
		{Name="Crate3", Size=Vector3.new(3, 4.5, 3), Pos=Vector3.new(11.5, 3, -22), Color="Brick yellow", Mat=Enum.Material.Wood},
		-- Street lamp posts
		{Name="LampPost1", Size=Vector3.new(0.5, 10, 0.5), Pos=Vector3.new(-20, 5, 0), Color="Medium stone grey", Mat=Enum.Material.Metal},
		{Name="LampPost2", Size=Vector3.new(0.5, 10, 0.5), Pos=Vector3.new(20, 5, 0), Color="Medium stone grey", Mat=Enum.Material.Metal},
		-- Bench
		{Name="Bench", Size=Vector3.new(5, 1, 1.5), Pos=Vector3.new(0, 0.5, 22), Color="Reddish brown", Mat=Enum.Material.Wood},
	}

	for _, p in ipairs(props) do
		local part = Instance.new("Part")
		part.Name = p.Name
		part.Size = p.Size
		part.Position = p.Pos
		part.Anchored = true
		part.BrickColor = BrickColor.new(p.Color)
		part.Material = p.Mat
		part.Parent = arenaFolder
	end

	-- Lamp lights (PointLights)
	for _, lampName in ipairs({"LampPost1", "LampPost2"}) do
		local lamp = arenaFolder:FindFirstChild(lampName)
		if lamp then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 200, 100)
			light.Brightness = 2
			light.Range = 30
			light.Parent = lamp

			-- Lamp head
			local head = Instance.new("Part")
			head.Name = lampName .. "Head"
			head.Size = Vector3.new(1.5, 0.5, 1.5)
			head.Position = lamp.Position + Vector3.new(0, 5.25, 0)
			head.Anchored = true
			head.BrickColor = BrickColor.new("Institutional white")
			head.Material = Enum.Material.Neon
			head.Parent = arenaFolder
		end
	end

	-- Spawn platform (invisible, just for positioning)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "SpawnLocation"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(0, 0.5, 10)
	spawnLocation.Anchored = true
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Parent = arenaFolder
end

------------------------------------------------------------
-- ENEMY SPAWNING & AI
------------------------------------------------------------
local function getRandomSpawnPos()
	-- Spawn from edges of the arena
	local side = math.random(1, 4)
	local x, z
	if side == 1 then -- left
		x = -ARENA_WIDTH/2 + 2
		z = math.random(-ARENA_DEPTH/2 + 5, ARENA_DEPTH/2 - 5)
	elseif side == 2 then -- right
		x = ARENA_WIDTH/2 - 2
		z = math.random(-ARENA_DEPTH/2 + 5, ARENA_DEPTH/2 - 5)
	elseif side == 3 then -- back
		x = math.random(-ARENA_WIDTH/2 + 5, ARENA_WIDTH/2 - 5)
		z = -ARENA_DEPTH/2 + 2
	else -- front
		x = math.random(-ARENA_WIDTH/2 + 5, ARENA_WIDTH/2 - 5)
		z = ARENA_DEPTH/2 - 2
	end
	return Vector3.new(x, 3, z)
end

local function findNearestPlayer(position)
	local nearest = nil
	local nearestDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local dist = (player.Character.HumanoidRootPart.Position - position).Magnitude
				if dist < nearestDist then
					nearest = player.Character
					nearestDist = dist
				end
			end
		end
	end
	return nearest, nearestDist
end

local function spawnEnemy(typeName, waveNum)
	local enemyDef = EnemyTypes.Types[typeName]
	if not enemyDef then return end

	local healthMult = EnemyTypes.GetHealthMultiplier(waveNum)
	local spawnPos = getRandomSpawnPos()

	local model = Utils.CreateNPCModel(
		enemyDef.Name,
		spawnPos,
		enemyDef.Color,
		enemyDef.ScaleMultiplier
	)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local maxHP = math.floor(enemyDef.Health * healthMult)
	humanoid.MaxHealth = maxHP
	humanoid.Health = maxHP
	humanoid.WalkSpeed = enemyDef.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayDistance = 100

	-- Store enemy data
	local enemyData = Instance.new("Configuration")
	enemyData.Name = "EnemyData"
	enemyData.Parent = model

	local typeVal = Instance.new("StringValue")
	typeVal.Name = "Type"
	typeVal.Value = typeName
	typeVal.Parent = enemyData

	local scoreVal = Instance.new("IntValue")
	scoreVal.Name = "ScoreValue"
	scoreVal.Value = enemyDef.ScoreValue
	scoreVal.Parent = enemyData

	local lastAttack = Instance.new("NumberValue")
	lastAttack.Name = "LastAttack"
	lastAttack.Value = 0
	lastAttack.Parent = enemyData

	-- Health bar
	Utils.CreateHealthBar(model, maxHP)

	model.Parent = enemiesFolder
	enemiesAlive = enemiesAlive + 1

	-- Notify clients for spawn effect
	SpawnEffectEvent:FireAllClients(model.PrimaryPart.Position)

	-- Death handling
	humanoid.Died:Connect(function()
		enemiesAlive = enemiesAlive - 1

		-- Award score
		local scoreValue = enemyDef.ScoreValue
		totalScore = totalScore + scoreValue
		ScoreEvent:FireAllClients("kill", scoreValue, totalScore)

		task.wait(1)
		if model and model.Parent then
			model:Destroy()
		end

		-- Check wave completion
		if enemiesAlive <= 0 and gameState == "Playing" then
			task.wait(2)
			startNextWave()
		end
	end)

	return model
end

------------------------------------------------------------
-- ENEMY AI LOOP
------------------------------------------------------------
local function runEnemyAI()
	while gameState == "Playing" do
		for _, enemy in ipairs(enemiesFolder:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart then
				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				local data = enemy:FindFirstChild("EnemyData")
				if humanoid and humanoid.Health > 0 and data then
					local typeName = data:FindFirstChild("Type") and data.Type.Value or "Thug"
					local enemyDef = EnemyTypes.Types[typeName]
					if enemyDef then
						local target, dist = findNearestPlayer(enemy.PrimaryPart.Position)
						if target and dist <= enemyDef.AggroRange then
							if dist <= enemyDef.AttackRange then
								-- Attack
								local lastAtk = data:FindFirstChild("LastAttack")
								local now = tick()
								if lastAtk and (now - lastAtk.Value) >= enemyDef.AttackCooldown then
									lastAtk.Value = now
									-- Deal damage to player
									local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
									if targetHumanoid and targetHumanoid.Health > 0 then
										-- Check if player is blocking
										local isBlocking = false
										local blockVal = target:FindFirstChild("IsBlocking")
										if blockVal and blockVal.Value then
											isBlocking = true
										end

										local dmg = enemyDef.Damage
										if isBlocking then
											dmg = math.floor(dmg * (1 - CombatConfig.BlockDamageReduction))
										end
										targetHumanoid:TakeDamage(dmg)

										-- Notify the hit player's client
										local player = Players:GetPlayerFromCharacter(target)
										if player then
											DamageEvent:FireClient(player, dmg, isBlocking, enemy.PrimaryPart.Position)
										end

										-- Visual feedback: enemy attack flash
										EnemyHitEvent:FireAllClients(enemy, "attack")
									end
								end
							else
								-- Move toward target
								humanoid:MoveTo(target.HumanoidRootPart.Position)
							end
						end
					end
				end
			end
		end
		task.wait(0.2) -- AI tick rate
	end
end

------------------------------------------------------------
-- WAVE MANAGEMENT
------------------------------------------------------------
function startNextWave()
	if gameState ~= "Playing" then return end

	currentWave = currentWave + 1
	GameStateEvent:FireAllClients("WaveStart", currentWave)

	task.wait(3) -- Brief pause before spawning

	local waveDef = EnemyTypes.GetWave(currentWave)
	for _, group in ipairs(waveDef) do
		for i = 1, group.Count do
			spawnEnemy(group.Type, currentWave)
			task.wait(0.5) -- Stagger spawns
		end
	end
end

------------------------------------------------------------
-- GAME FLOW
------------------------------------------------------------
local function cleanupGame()
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		enemy:Destroy()
	end
	enemiesAlive = 0
	currentWave = 0
	totalScore = 0
	playerScores = {}
	playerDeaths = {}
end

local function checkAllPlayersDead()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return false
			end
		end
	end
	return true
end

local function startGame()
	if gameState == "Playing" then return end

	cleanupGame()
	gameState = "Playing"
	GameStateEvent:FireAllClients("GameStart", 0)

	-- Respawn all players
	for _, player in ipairs(Players:GetPlayers()) do
		player:LoadCharacter()
		playerDeaths[player.UserId] = false
	end

	task.wait(2)
	startNextWave()

	-- Start AI loop in separate thread
	task.spawn(runEnemyAI)
end

local function endGame()
	gameState = "GameOver"
	GameStateEvent:FireAllClients("GameOver", totalScore)

	-- Clean up enemies
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		enemy:Destroy()
	end
	enemiesAlive = 0
end

------------------------------------------------------------
-- ATTACK PROCESSING
------------------------------------------------------------
AttackEvent.OnServerEvent:Connect(function(player, attackType, targetPosition, attackDirection)
	if gameState ~= "Playing" then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local config = CombatConfig.Attacks[attackType]
	if not config then return end

	local charPos = player.Character.HumanoidRootPart.Position

	-- Find enemies in range
	local hitEnemies = Utils.GetEnemiesInRange(charPos, config.Range, enemiesFolder)

	local hitSomething = false
	for _, enemy in ipairs(hitEnemies) do
		local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
		if enemyHumanoid and enemyHumanoid.Health > 0 then
			-- Direction check: only hit enemies roughly in front
			local toEnemy = (enemy.PrimaryPart.Position - charPos).Unit
			local facing = attackDirection or player.Character.HumanoidRootPart.CFrame.LookVector
			local dot = toEnemy:Dot(facing)
			if dot > 0.2 then -- roughly in front (wide arc for beat-em-up feel)
				local dmg = config.Damage
				enemyHumanoid:TakeDamage(dmg)
				hitSomething = true

				-- Knockback
				local knockDir = toEnemy * config.KnockbackForce
				local data = enemy:FindFirstChild("EnemyData")
				local typeName = data and data:FindFirstChild("Type") and data.Type.Value or "Thug"
				local resist = EnemyTypes.Types[typeName] and EnemyTypes.Types[typeName].KnockbackResist or 0
				local actualKnock = knockDir * (1 - resist)
				if enemy.PrimaryPart then
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
					bv.Velocity = Vector3.new(actualKnock.X, 0, actualKnock.Z)
					bv.Parent = enemy.PrimaryPart
					game:GetService("Debris"):AddItem(bv, 0.2)
				end

				-- Notify all clients of hit for visual effects
				EnemyHitEvent:FireAllClients(enemy, "hit", charPos)

				-- Update health bar
				local hb = enemy:FindFirstChild("HealthBar")
				if hb then
					local bg = hb:FindFirstChild("Background")
					if bg then
						local fill = bg:FindFirstChild("Fill")
						if fill then
							fill.Size = UDim2.new(math.max(0, enemyHumanoid.Health / enemyHumanoid.MaxHealth), 0, 1, 0)
						end
					end
				end
			end
		end
	end

	if hitSomething then
		-- Award hit score
		totalScore = totalScore + CombatConfig.ScorePerHit
		ScoreEvent:FireClient(player, "hit", CombatConfig.ScorePerHit, totalScore)
	end
end)

------------------------------------------------------------
-- PLAYER DEATH TRACKING
------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Add blocking value
		local blockVal = Instance.new("BoolValue")
		blockVal.Name = "IsBlocking"
		blockVal.Value = false
		blockVal.Parent = character

		-- Add dodge iframe value
		local dodgeVal = Instance.new("BoolValue")
		dodgeVal.Name = "IsDodging"
		dodgeVal.Value = false
		dodgeVal.Parent = character

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			playerDeaths[player.UserId] = true
			PlayerDiedEvent:FireClient(player)

			task.wait(0.5)
			if gameState == "Playing" and checkAllPlayersDead() then
				endGame()
			end
		end)
	end)

	-- Auto-start game when first player joins lobby
	if gameState == "Lobby" then
		task.wait(5) -- Give a few seconds to load
		if gameState == "Lobby" and #Players:GetPlayers() > 0 then
			startGame()
		end
	end
end)

-- Handle restart request
RequestRestartEvent.OnServerEvent:Connect(function(player)
	if gameState == "GameOver" then
		startGame()
	end
end)

-- Handle block state from client
local BlockEvent = createRemote("RemoteEvent", "BlockEvent")
BlockEvent.OnServerEvent:Connect(function(player, isBlocking)
	if player.Character then
		local bv = player.Character:FindFirstChild("IsBlocking")
		if bv then
			bv.Value = isBlocking
		end
	end
end)

-- Handle dodge from client
local DodgeEvent = createRemote("RemoteEvent", "DodgeEvent")
DodgeEvent.OnServerEvent:Connect(function(player, direction)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local dodgeVal = player.Character:FindFirstChild("IsDodging")
	if dodgeVal then
		dodgeVal.Value = true
		task.delay(CombatConfig.DodgeIFrames, function()
			if dodgeVal then
				dodgeVal.Value = false
			end
		end)
	end

	-- Apply dodge velocity
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
	bv.Velocity = direction * CombatConfig.DodgeDistance
	bv.Parent = player.Character.HumanoidRootPart
	game:GetService("Debris"):AddItem(bv, 0.3)
end)

------------------------------------------------------------
-- INIT
------------------------------------------------------------
buildArena()
print("[BrawlAlley] Arena built. Waiting for players...")

-- If players already in game (studio testing), start immediately
if #Players:GetPlayers() > 0 then
	task.wait(3)
	if gameState == "Lobby" then
		startGame()
	end
end
