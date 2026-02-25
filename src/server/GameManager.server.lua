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
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))

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
local EnemyAnimEvent = createRemote("RemoteEvent", "EnemyAnimEvent")
local ScreenShakeEvent = createRemote("RemoteEvent", "ScreenShakeEvent")
local ComicBubbleEvent = createRemote("RemoteEvent", "ComicBubbleEvent")

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
-- SPAWN POINTS (edges/entrances of arena)
------------------------------------------------------------
local SPAWN_POINTS = {
	-- Left alley mouth
	{pos = Vector3.new(-ARENA_WIDTH/2 + 3, 3, -10), name = "LeftAlley1"},
	{pos = Vector3.new(-ARENA_WIDTH/2 + 3, 3, 10), name = "LeftAlley2"},
	-- Right alley mouth
	{pos = Vector3.new(ARENA_WIDTH/2 - 3, 3, -10), name = "RightAlley1"},
	{pos = Vector3.new(ARENA_WIDTH/2 - 3, 3, 10), name = "RightAlley2"},
	-- Back wall (behind dumpsters/crates)
	{pos = Vector3.new(-20, 3, -ARENA_DEPTH/2 + 3), name = "BackLeft"},
	{pos = Vector3.new(15, 3, -ARENA_DEPTH/2 + 3), name = "BackRight"},
	-- Front entrance
	{pos = Vector3.new(0, 3, ARENA_DEPTH/2 - 3), name = "FrontCenter"},
	-- Rooftop drop points (spawn higher, they fall down)
	{pos = Vector3.new(-25, 12, -5), name = "RooftopLeft"},
	{pos = Vector3.new(30, 12, 5), name = "RooftopRight"},
}

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

	-- Front wall
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
	local sp = SPAWN_POINTS[math.random(1, #SPAWN_POINTS)]
	-- Add slight randomness so enemies don't stack
	local jitter = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	return sp.pos + jitter
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

	local lastTaunt = Instance.new("NumberValue")
	lastTaunt.Name = "LastTaunt"
	lastTaunt.Value = 0
	lastTaunt.Parent = enemyData

	local comboStep = Instance.new("IntValue")
	comboStep.Name = "ComboStep"
	comboStep.Value = 0
	comboStep.Parent = enemyData

	local lastComboTime = Instance.new("NumberValue")
	lastComboTime.Name = "LastComboTime"
	lastComboTime.Value = 0
	lastComboTime.Parent = enemyData

	local isTaunting = Instance.new("BoolValue")
	isTaunting.Name = "IsTaunting"
	isTaunting.Value = false
	isTaunting.Parent = enemyData

	-- State: "approaching" until first taunt, then "fighting"
	local aiState = Instance.new("StringValue")
	aiState.Name = "AIState"
	aiState.Value = "approaching" -- approaching, fighting
	aiState.Parent = enemyData

	local hasFirstTaunted = Instance.new("BoolValue")
	hasFirstTaunted.Name = "HasFirstTaunted"
	hasFirstTaunted.Value = false
	hasFirstTaunted.Parent = enemyData

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
-- ENEMY AI HELPERS
------------------------------------------------------------
local function doEnemyTaunt(enemy, enemyDef, data)
	local taunting = data:FindFirstChild("IsTaunting")
	if taunting then taunting.Value = true end

	local typeName = data.Type.Value
	EnemyAnimEvent:FireAllClients(enemy, "taunt", typeName)

	if typeName == "Thug" then
		AnimationManager.PlayThugTaunt(enemy)
	elseif typeName == "Brawler" then
		AnimationManager.PlayBrawlerTaunt(enemy)
	elseif typeName == "Speedster" then
		AnimationManager.PlaySpeedsterTaunt(enemy)
	end

	-- Show taunt text
	AnimationManager.ShowTauntText(enemy, enemyDef.TauntText, 2)

	local lastTauntVal = data:FindFirstChild("LastTaunt")
	if lastTauntVal then lastTauntVal.Value = tick() end

	local tauntDuration = (typeName == "Brawler") and 1.8 or 1.2
	task.delay(tauntDuration, function()
		if taunting and taunting.Parent then
			taunting.Value = false
		end
	end)
end

local function doEnemyComboHit(enemy, enemyDef, data, target, hitIndex)
	local typeName = data.Type.Value
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then return end

	-- Play attack animation
	EnemyAnimEvent:FireAllClients(enemy, "attack", typeName, hitIndex)
	if typeName == "Thug" then
		AnimationManager.PlayThugAttack(enemy, hitIndex)
	elseif typeName == "Brawler" then
		AnimationManager.PlayBrawlerAttack(enemy, hitIndex)
	elseif typeName == "Speedster" then
		AnimationManager.PlaySpeedsterAttack(enemy, hitIndex)
	end

	-- Check blocking
	local isBlocking = false
	local blockVal = target:FindFirstChild("IsBlocking")
	if blockVal and blockVal.Value then
		isBlocking = true
	end

	-- Calculate damage with combo multiplier
	local dmgMult = enemyDef.ComboDamageMultipliers and enemyDef.ComboDamageMultipliers[hitIndex] or 1.0
	local dmg = math.floor(enemyDef.Damage * dmgMult)
	if isBlocking then
		dmg = math.floor(dmg * (1 - CombatConfig.BlockDamageReduction))
	end
	targetHumanoid:TakeDamage(dmg)

	-- Notify hit player
	local hitPlayer = Players:GetPlayerFromCharacter(target)
	if hitPlayer then
		DamageEvent:FireClient(hitPlayer, dmg, isBlocking, enemy.PrimaryPart.Position)
		if dmgMult >= 1.3 then
			ScreenShakeEvent:FireClient(hitPlayer, dmgMult * 5, 0.3)
		end
	end

	-- Visual feedback
	EnemyHitEvent:FireAllClients(enemy, "attack")
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
					-- Skip if currently taunting
					local taunting = data:FindFirstChild("IsTaunting")
					if taunting and taunting.Value then
						continue
					end

					local typeName = data:FindFirstChild("Type") and data.Type.Value or "Thug"
					local enemyDef = EnemyTypes.Types[typeName]
					if enemyDef then
						local target, dist = findNearestPlayer(enemy.PrimaryPart.Position)
						if target then
							local aiState = data:FindFirstChild("AIState")
							local hasFirstTaunted = data:FindFirstChild("HasFirstTaunted")
							local now = tick()

							-- APPROACHING STATE: walk toward player, do first taunt at medium range
							if aiState and aiState.Value == "approaching" then
								-- First taunt when at medium range (15-25 studs)
								if hasFirstTaunted and not hasFirstTaunted.Value and dist <= 25 and dist >= 8 then
									hasFirstTaunted.Value = true
									doEnemyTaunt(enemy, enemyDef, data)
									continue
								end

								-- If close enough, switch to fighting
								if dist <= enemyDef.AttackRange + 2 then
									if aiState then aiState.Value = "fighting" end
								else
									-- Keep walking toward player
									humanoid:MoveTo(target.HumanoidRootPart.Position)
									continue
								end
							end

							-- FIGHTING STATE: normal combat AI with high taunt chance
							if dist <= enemyDef.AggroRange then
								-- Check for taunt opportunity (higher chance: 50-70%)
								local lastTauntVal = data:FindFirstChild("LastTaunt")
								local tauntCooldown = enemyDef.TauntCooldown or 8
								-- Reduce cooldown for more frequent taunts (4-8 seconds)
								local actualCooldown = math.max(4, tauntCooldown * 0.6)
								if lastTauntVal and (now - lastTauntVal.Value) >= actualCooldown then
									-- Much higher taunt chance
									local tauntChance = math.max(0.5, (enemyDef.TauntChance or 0.3) * 2)
									if math.random() < tauntChance then
										doEnemyTaunt(enemy, enemyDef, data)
										continue
									end
								end

								if dist <= enemyDef.AttackRange then
									-- Attack with combo system
									local lastAtk = data:FindFirstChild("LastAttack")
									local comboStepVal = data:FindFirstChild("ComboStep")
									local lastComboVal = data:FindFirstChild("LastComboTime")

									if lastAtk and comboStepVal then
										local comboHits = enemyDef.ComboHits or 1
										local comboCooldown = enemyDef.ComboCooldown or 0.5
										local currentStep = comboStepVal.Value

										if currentStep > 0 and lastComboVal and (now - lastComboVal.Value) < comboCooldown + 0.3 then
											if (now - lastComboVal.Value) >= comboCooldown then
												currentStep = currentStep + 1
												if currentStep > comboHits then
													comboStepVal.Value = 0
													lastAtk.Value = now
												else
													comboStepVal.Value = currentStep
													lastComboVal.Value = now
													doEnemyComboHit(enemy, enemyDef, data, target, currentStep)
												end
											end
										elseif currentStep == 0 and (now - lastAtk.Value) >= enemyDef.AttackCooldown then
											comboStepVal.Value = 1
											if lastComboVal then lastComboVal.Value = now end
											lastAtk.Value = now
											doEnemyComboHit(enemy, enemyDef, data, target, 1)
										else
											if currentStep > 0 and lastComboVal and (now - lastComboVal.Value) >= comboCooldown + 0.3 then
												comboStepVal.Value = 0
											end
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
		end
		task.wait(0.15)
	end
end

------------------------------------------------------------
-- WAVE MANAGEMENT
------------------------------------------------------------
function startNextWave()
	if gameState ~= "Playing" then return end

	currentWave = currentWave + 1
	GameStateEvent:FireAllClients("WaveStart", currentWave)

	task.wait(3)

	local waveDef = EnemyTypes.GetWave(currentWave)
	for _, group in ipairs(waveDef) do
		for i = 1, group.Count do
			spawnEnemy(group.Type, currentWave)
			task.wait(0.8) -- Slightly more stagger so enemies approach in sequence
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
			local toEnemy = (enemy.PrimaryPart.Position - charPos).Unit
			local facing = attackDirection or player.Character.HumanoidRootPart.CFrame.LookVector
			local dot = toEnemy:Dot(facing)
			if dot > 0.2 then
				local dmg = config.Damage
				enemyHumanoid:TakeDamage(dmg)
				hitSomething = true

				-- Knockback — more dramatic for heavy hits
				local knockMult = 1.0
				if attackType == "HeavyAttack" then
					knockMult = 1.5
				end
				local knockDir = toEnemy * config.KnockbackForce * knockMult
				local data = enemy:FindFirstChild("EnemyData")
				local typeName = data and data:FindFirstChild("Type") and data.Type.Value or "Thug"
				local resist = EnemyTypes.Types[typeName] and EnemyTypes.Types[typeName].KnockbackResist or 0
				local actualKnock = knockDir * (1 - resist)

				-- Heavy hits: add upward force for dramatic stagger
				local yForce = 0
				if attackType == "HeavyAttack" then
					yForce = 15
				end

				if enemy.PrimaryPart then
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
					bv.Velocity = Vector3.new(actualKnock.X, yForce, actualKnock.Z)
					bv.Parent = enemy.PrimaryPart
					game:GetService("Debris"):AddItem(bv, 0.25)
				end

				-- Fire comic bubble event to all clients
				-- Determine bubble type
				local bubbleType = "light"
				if attackType == "HeavyAttack" then
					bubbleType = "heavy"
				end
				ComicBubbleEvent:FireAllClients(enemy, bubbleType, enemy.PrimaryPart.Position)

				-- Notify all clients of hit for visual effects
				EnemyHitEvent:FireAllClients(enemy, "hit", charPos, attackType)

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
		totalScore = totalScore + CombatConfig.ScorePerHit
		ScoreEvent:FireClient(player, "hit", CombatConfig.ScorePerHit, totalScore)
	end
end)

------------------------------------------------------------
-- PLAYER DEATH TRACKING
------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local blockVal = Instance.new("BoolValue")
		blockVal.Name = "IsBlocking"
		blockVal.Value = false
		blockVal.Parent = character

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

	if gameState == "Lobby" then
		task.wait(5)
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

if #Players:GetPlayers() > 0 then
	task.wait(3)
	if gameState == "Lobby" then
		startGame()
	end
end
