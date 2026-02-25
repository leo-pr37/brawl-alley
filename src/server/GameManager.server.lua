--[[
	GameManager (Server)
	Manages the overall game state: lobby, waves, game over, restart.
	Handles enemy spawning, damage processing, and score tracking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local EnemyTypes = require(Shared:WaitForChild("EnemyTypes"))
local Utils = require(Shared:WaitForChild("Utils"))
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))
local ArenaBuilder = require(script.Parent:WaitForChild("ArenaBuilder"))

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
local RequestGameStartEvent = createRemote("RemoteEvent", "RequestGameStartEvent")
local SpawnEffectEvent = createRemote("RemoteEvent", "SpawnEffectEvent")
local EnemyAnimEvent = createRemote("RemoteEvent", "EnemyAnimEvent")
local ScreenShakeEvent = createRemote("RemoteEvent", "ScreenShakeEvent")
local ComicBubbleEvent = createRemote("RemoteEvent", "ComicBubbleEvent")
local ItemInteractEvent = createRemote("RemoteEvent", "ItemInteractEvent")
local HeldItemStateEvent = createRemote("RemoteEvent", "HeldItemStateEvent")
local BlockEvent = createRemote("RemoteEvent", "BlockEvent")
local DodgeEvent = createRemote("RemoteEvent", "DodgeEvent")
local TeamStatusEvent = createRemote("RemoteEvent", "TeamStatusEvent")

-- Game state
local gameState = "Lobby" -- Lobby, Playing, GameOver
local currentWave = 0
local enemiesAlive = 0
local totalScore = 0 -- shared score for co-op
local playerScores = {} -- per-player scores
local playerDeaths = {} -- track dead players
local heldItems = {}
local itemUseCooldowns = {}
local itemSpawnerRunning = false
local enemyHeldItems = setmetatable({}, { __mode = "k" })
local enemyMoveAnimTimes = setmetatable({}, { __mode = "k" })
local DIFFICULTY_SETTINGS = {
	Easy = {HealthMultiplier = 0.8, DamageMultiplier = 0.8, SpeedMultiplier = 0.9},
	Normal = {HealthMultiplier = 1.0, DamageMultiplier = 1.0, SpeedMultiplier = 1.0},
	Hard = {HealthMultiplier = 1.25, DamageMultiplier = 1.25, SpeedMultiplier = 1.1},
}
local DEFAULT_DIFFICULTY = "Normal"
local currentSelectedLevel = EnemyTypes.DefaultLevel
local currentSelectedDifficulty = DEFAULT_DIFFICULTY
local currentDifficultySettings = DIFFICULTY_SETTINGS[DEFAULT_DIFFICULTY]
local MAX_TEAM_PLAYERS = 4
local activeTeam = {}

-- R15 is now handled by CharacterBuilder (shared) for NPCs
-- and game avatar settings for player characters.

-- Folders
local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"
enemiesFolder.Parent = workspace

local arenaFolder = Instance.new("Folder")
arenaFolder.Name = "Arena"
arenaFolder.Parent = workspace

local groundItemsFolder = Instance.new("Folder")
groundItemsFolder.Name = "GroundItems"
groundItemsFolder.Parent = workspace

-- Arena dimensions
local ARENA_WIDTH = 120
local ARENA_DEPTH = 80
local ARENA_CENTER = Vector3.new(0, 0, 0)

local function resolveLevel(levelKey)
	if EnemyTypes.Levels[levelKey] then
		return levelKey
	end
	return EnemyTypes.DefaultLevel
end

local function resolveDifficulty(difficultyKey)
	if DIFFICULTY_SETTINGS[difficultyKey] then
		return difficultyKey
	end
	return DEFAULT_DIFFICULTY
end

------------------------------------------------------------
-- ENEMY SPAWNING & AI
------------------------------------------------------------
local function getRandomSpawnPos()
	return ArenaBuilder.GetRandomSpawnPos(currentSelectedLevel)
end

local function getRandomGroundItemPos()
	local margin = 6
	local x = math.random(math.floor(-ARENA_WIDTH / 2 + margin), math.floor(ARENA_WIDTH / 2 - margin))
	local z = math.random(math.floor(-ARENA_DEPTH / 2 + margin), math.floor(ARENA_DEPTH / 2 - margin))
	return Vector3.new(x, 2, z)
end

local function createGroundItem(itemType)
	local item = Instance.new("Part")
	item.Name = itemType .. "Item"
	item.Anchored = true
	item.CanCollide = true
	item.Position = getRandomGroundItemPos()
	item:SetAttribute("ItemType", itemType)
	item:SetAttribute("IsGroundItem", true)

	if itemType == "Health" then
		item.Size = Vector3.new(2, 2, 2)
		item.Shape = Enum.PartType.Ball
		item.BrickColor = BrickColor.new("Lime green")
		item.Material = Enum.Material.Neon
	elseif itemType == "Weapon" then
		item.Size = Vector3.new(1, 3, 1)
		item.BrickColor = BrickColor.new("Really black")
		item.Material = Enum.Material.Metal
	else
		item.Size = Vector3.new(2.5, 2.5, 2.5)
		item.Shape = Enum.PartType.Ball
		item.BrickColor = BrickColor.new("Dark stone grey")
		item.Material = Enum.Material.Slate
	end

	local label = Instance.new("BillboardGui")
	label.Name = "ItemLabel"
	label.Size = UDim2.new(0, 100, 0, 24)
	label.StudsOffset = Vector3.new(0, 2.5, 0)
	label.AlwaysOnTop = true
	label.Parent = item

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Text = itemType:upper()
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.5
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Parent = label

	item.Parent = groundItemsFolder
	return item
end

local function pickRandomItemType()
	local roll = math.random()
	if roll < 0.35 then
		return "Health"
	elseif roll < 0.65 then
		return "Weapon"
	end
	return "Rock"
end

local function spawnGroundItem()
	if gameState ~= "Playing" then return end
	if #groundItemsFolder:GetChildren() >= CombatConfig.Items.MaxGroundItems then return end
	createGroundItem(pickRandomItemType())
end

local function runGroundItemSpawner()
	if itemSpawnerRunning then return end
	itemSpawnerRunning = true
	while gameState == "Playing" do
		local delaySeconds = math.random(CombatConfig.Items.SpawnIntervalMin, CombatConfig.Items.SpawnIntervalMax)
		task.wait(delaySeconds)
		if gameState ~= "Playing" then
			break
		end
		spawnGroundItem()
	end
	itemSpawnerRunning = false
end

local function findNearestGroundItem(position, maxDistance)
	local nearest = nil
	local nearestDist = maxDistance
	for _, item in ipairs(groundItemsFolder:GetChildren()) do
		if item:IsA("BasePart") and item:GetAttribute("IsGroundItem") then
			local dist = (item.Position - position).Magnitude
			if dist <= nearestDist then
				nearest = item
				nearestDist = dist
			end
		end
	end
	return nearest
end

local function clearHeldItem(player)
	local held = heldItems[player.UserId]
	if held and held.Part and held.Part.Parent then
		held.Part:Destroy()
	end
	heldItems[player.UserId] = nil
	itemUseCooldowns[player.UserId] = nil
	HeldItemStateEvent:FireClient(player, nil)
end

local function dropHeldItem(player, dropDirection)
	local held = heldItems[player.UserId]
	if not held or not held.Part or not held.Part.Parent then
		heldItems[player.UserId] = nil
		HeldItemStateEvent:FireClient(player, nil)
		return
	end

	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		held.Part:Destroy()
		heldItems[player.UserId] = nil
		HeldItemStateEvent:FireClient(player, nil)
		return
	end

	local hrp = player.Character.HumanoidRootPart
	local dir = (dropDirection and dropDirection.Magnitude > 0) and dropDirection.Unit or hrp.CFrame.LookVector

	for _, child in ipairs(held.Part:GetChildren()) do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	held.Part.Anchored = true
	held.Part.CanCollide = true
	held.Part.Massless = false
	held.Part.Position = hrp.Position + dir * 3 + Vector3.new(0, 1, 0)
	held.Part.Parent = groundItemsFolder
	held.Part:SetAttribute("ItemType", held.Type)
	held.Part:SetAttribute("IsGroundItem", true)

	heldItems[player.UserId] = nil
	itemUseCooldowns[player.UserId] = nil
	HeldItemStateEvent:FireClient(player, nil)
end

local function clearEnemyHeldItem(enemy)
	local held = enemyHeldItems[enemy]
	if held and held.Part and held.Part.Parent then
		held.Part:Destroy()
	end
	enemyHeldItems[enemy] = nil
end

local function maybePlayEnemyMoveAnim(enemy, typeName, moving)
	local now = tick()
	local last = enemyMoveAnimTimes[enemy] or 0
	if now - last < 0.18 then
		return
	end
	enemyMoveAnimTimes[enemy] = now
	AnimationManager.PlayEnemyLocomotion(enemy, typeName, moving)
end

local function enemyTryPickupItem(enemy, enemyHumanoid)
	if enemyHeldItems[enemy] or not enemy.PrimaryPart then
		return false
	end

	local nearestItem = findNearestGroundItem(enemy.PrimaryPart.Position, CombatConfig.Items.PickupRange * 0.8)
	if not nearestItem then
		return false
	end

	local itemType = nearestItem:GetAttribute("ItemType")
	if itemType == "Health" then
		if enemyHumanoid.Health < enemyHumanoid.MaxHealth then
			enemyHumanoid.Health = math.min(enemyHumanoid.MaxHealth, enemyHumanoid.Health + CombatConfig.Items.Health.HealAmount)
			nearestItem:Destroy()
			return true
		end
		return false
	end

	local attachPart = enemy:FindFirstChild("RightHand")
		or enemy:FindFirstChild("RightUpperArm")
		or enemy:FindFirstChild("HumanoidRootPart")
	if not attachPart then
		return false
	end

	nearestItem.Anchored = false
	nearestItem.CanCollide = false
	nearestItem.Massless = true
	nearestItem.CFrame = attachPart.CFrame * CFrame.new(0, -0.8, -1)
	nearestItem.Parent = enemy

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = nearestItem
	weld.Parent = nearestItem

	enemyHeldItems[enemy] = {
		Type = itemType,
		Part = nearestItem,
		LastUse = 0,
	}
	return true
end

local function enemyThrowAtPlayer(enemy, target, held, throwConfig)
	if not enemy.PrimaryPart or not target or not target:FindFirstChild("HumanoidRootPart") then
		clearEnemyHeldItem(enemy)
		return false
	end

	local rockPart = held.Part
	if not rockPart or not rockPart.Parent then
		clearEnemyHeldItem(enemy)
		return false
	end

	for _, child in ipairs(rockPart:GetChildren()) do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local origin = enemy.PrimaryPart.Position + Vector3.new(0, 1.5, 0)
	local targetPos = target.HumanoidRootPart.Position + Vector3.new(0, 1, 0)
	local dir = (targetPos - origin).Magnitude > 0 and (targetPos - origin).Unit or enemy.PrimaryPart.CFrame.LookVector

	rockPart.Anchored = false
	rockPart.CanCollide = true
	rockPart.Massless = false
	rockPart.CFrame = CFrame.new(origin)
	rockPart.Parent = workspace

	local hitDone = false
	local touchConnection
	touchConnection = rockPart.Touched:Connect(function(hit)
		if hitDone then return end
		if hit:IsDescendantOf(enemy) then return end
		local victim = hit:FindFirstAncestorOfClass("Model")
		local victimPlayer = victim and Players:GetPlayerFromCharacter(victim)
		if not victimPlayer then return end
		local victimHumanoid = victim:FindFirstChildOfClass("Humanoid")
		if not victimHumanoid or victimHumanoid.Health <= 0 then return end

		hitDone = true
		victimHumanoid:TakeDamage(throwConfig.ThrowDamage)
		DamageEvent:FireClient(victimPlayer, throwConfig.ThrowDamage, false, enemy.PrimaryPart.Position)
		EnemyHitEvent:FireAllClients(enemy, "hit", rockPart.Position, "EnemyItemThrow")
		if touchConnection then touchConnection:Disconnect() end
		rockPart:Destroy()
	end)

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = dir * throwConfig.ThrowSpeed + Vector3.new(0, 10, 0)
	bv.Parent = rockPart
	Debris:AddItem(bv, 0.25)
	Debris:AddItem(rockPart, throwConfig.ProjectileLifetime)
	task.delay(throwConfig.ProjectileLifetime, function()
		if touchConnection then touchConnection:Disconnect() end
	end)

	enemyHeldItems[enemy] = nil
	return true
end

local function enemyTryUseHeldItem(enemy, enemyDef, target, dist)
	local held = enemyHeldItems[enemy]
	if not held or not held.Part or not held.Part.Parent then
		enemyHeldItems[enemy] = nil
		return false
	end

	local now = tick()
	local cooldown = CombatConfig.Items.Weapon.SwingCooldown
	if held.Type == "Rock" then
		cooldown = CombatConfig.Items.Rock.ThrowCooldown
	end
	if now - (held.LastUse or 0) < cooldown then
		return false
	end

	if held.Type == "Weapon" then
		if dist > CombatConfig.Items.Weapon.SwingRange then
			return false
		end
		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		if not targetHumanoid or targetHumanoid.Health <= 0 then
			return false
		end
		held.LastUse = now
		targetHumanoid:TakeDamage(CombatConfig.Items.Weapon.SwingDamage)
		local hitPlayer = Players:GetPlayerFromCharacter(target)
		if hitPlayer then
			DamageEvent:FireClient(hitPlayer, CombatConfig.Items.Weapon.SwingDamage, false, enemy.PrimaryPart.Position)
		end
		EnemyHitEvent:FireAllClients(enemy, "attack", enemy.PrimaryPart.Position, "EnemyItemSwing")
		return true
	elseif held.Type == "Rock" then
		if dist > 30 then
			return false
		end
		held.LastUse = now
		return enemyThrowAtPlayer(enemy, target, held, CombatConfig.Items.Rock)
	end

	return false
end

local function updateEnemyHealthBar(enemy, enemyHumanoid)
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

local function applyEnemyKnockback(enemy, velocity, yForce, duration)
	if not enemy.PrimaryPart then return end
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.new(velocity.X, yForce or 0, velocity.Z)
	bv.Parent = enemy.PrimaryPart
	Debris:AddItem(bv, duration or 0.2)
end

local function tryMeleeItemSwing(player, damage, range, knockbackForce)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return false end
	local charPos = player.Character.HumanoidRootPart.Position
	local facing = player.Character.HumanoidRootPart.CFrame.LookVector
	local hitSomething = false

	for _, enemy in ipairs(Utils.GetEnemiesInRange(charPos, range, enemiesFolder)) do
		local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
		if enemyHumanoid and enemyHumanoid.Health > 0 and enemy.PrimaryPart then
			local toEnemy = (enemy.PrimaryPart.Position - charPos).Unit
			if toEnemy:Dot(facing) > 0.1 then
				enemyHumanoid:TakeDamage(damage)
				updateEnemyHealthBar(enemy, enemyHumanoid)
				applyEnemyKnockback(enemy, toEnemy * knockbackForce, 8, 0.2)
				EnemyHitEvent:FireAllClients(enemy, "hit", charPos, "ItemSwing")
				ComicBubbleEvent:FireAllClients(enemy, "heavy", enemy.PrimaryPart.Position)
				hitSomething = true
			end
		end
	end

	return hitSomething
end

local function throwRock(player, rockPart, throwDirection, throwConfig, attackTag)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		if rockPart and rockPart.Parent then
			rockPart:Destroy()
		end
		return
	end

	throwConfig = throwConfig or CombatConfig.Items.Rock
	attackTag = attackTag or "RockThrow"

	local hrp = player.Character.HumanoidRootPart
	local dir = (throwDirection and throwDirection.Magnitude > 0) and throwDirection.Unit or hrp.CFrame.LookVector
	local lifetime = throwConfig.ProjectileLifetime
	local hitDone = false
	local touchConnection = nil

	for _, child in ipairs(rockPart:GetChildren()) do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	rockPart.Anchored = false
	rockPart.CanCollide = true
	rockPart.Massless = false
	rockPart.CFrame = CFrame.new(hrp.Position + dir * 2 + Vector3.new(0, 1.5, 0))
	rockPart.Parent = workspace

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = dir * throwConfig.ThrowSpeed + Vector3.new(0, 12, 0)
	bv.Parent = rockPart
	Debris:AddItem(bv, 0.25)

	touchConnection = rockPart.Touched:Connect(function(hit)
		if hitDone then return end
		if player.Character and hit:IsDescendantOf(player.Character) then return end
		local enemy = hit:FindFirstAncestorOfClass("Model")
		if not enemy or enemy.Parent ~= enemiesFolder then return end
		local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
		if not enemyHumanoid or enemyHumanoid.Health <= 0 then return end

		hitDone = true
		enemyHumanoid:TakeDamage(throwConfig.ThrowDamage)
		updateEnemyHealthBar(enemy, enemyHumanoid)
		totalScore = totalScore + CombatConfig.ScorePerHit
		ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
		if enemy.PrimaryPart then
			local toEnemy = (enemy.PrimaryPart.Position - rockPart.Position).Unit
			applyEnemyKnockback(enemy, toEnemy * (throwConfig.KnockbackForce or 35), 10, 0.25)
			ComicBubbleEvent:FireAllClients(enemy, "heavy", enemy.PrimaryPart.Position)
		end
		EnemyHitEvent:FireAllClients(enemy, "hit", rockPart.Position, attackTag)
		if touchConnection then
			touchConnection:Disconnect()
		end
		rockPart:Destroy()
	end)

	task.delay(lifetime, function()
		if touchConnection then
			touchConnection:Disconnect()
		end
	end)
	Debris:AddItem(rockPart, lifetime)
end

local function findNearestPlayer(position)
	local nearest = nil
	local nearestDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if not activeTeam[player.UserId] then
			continue
		end
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

local function getActiveTeamPlayers()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if activeTeam[player.UserId] then
			table.insert(result, player)
		end
	end
	return result
end

local function refreshLobbyTeamStatus()
	local playerCount = #Players:GetPlayers()
	local activeCount = math.min(playerCount, MAX_TEAM_PLAYERS)
	local overflow = math.max(playerCount - MAX_TEAM_PLAYERS, 0)
	TeamStatusEvent:FireAllClients(activeCount, MAX_TEAM_PLAYERS, overflow)
end

local function countNearbyEnemies(position, radius, excludedEnemy)
	local count = 0
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy ~= excludedEnemy and enemy:IsA("Model") and enemy.PrimaryPart then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				if (enemy.PrimaryPart.Position - position).Magnitude <= radius then
					count = count + 1
				end
			end
		end
	end
	return count
end

local function spawnEnemy(typeName, waveNum)
	local enemyDef = EnemyTypes.Types[typeName]
	if not enemyDef then return end

	local healthMult = EnemyTypes.GetHealthMultiplier(waveNum)
	local difficulty = currentDifficultySettings or DIFFICULTY_SETTINGS[DEFAULT_DIFFICULTY]
	local spawnPos = getRandomSpawnPos()

	local model = Utils.CreateNPCModel(
		enemyDef.Name,
		spawnPos,
		enemyDef.Color,
		enemyDef.ScaleMultiplier,
		typeName
	)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local maxHP = math.max(1, math.floor(enemyDef.Health * healthMult * difficulty.HealthMultiplier))
	humanoid.MaxHealth = maxHP
	humanoid.Health = maxHP
	humanoid.WalkSpeed = enemyDef.WalkSpeed * difficulty.SpeedMultiplier
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

	local damageMultVal = Instance.new("NumberValue")
	damageMultVal.Name = "DamageMultiplier"
	damageMultVal.Value = difficulty.DamageMultiplier
	damageMultVal.Parent = enemyData

	local baseWalkSpeedVal = Instance.new("NumberValue")
	baseWalkSpeedVal.Name = "BaseWalkSpeed"
	baseWalkSpeedVal.Value = humanoid.WalkSpeed
	baseWalkSpeedVal.Parent = enemyData

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

	local engageDistance = Instance.new("NumberValue")
	engageDistance.Name = "EngageDistance"
	engageDistance.Value = (enemyDef.AttackRange or 5) + math.random(3, 8)
	engageDistance.Parent = enemyData

	-- Health bar
	Utils.CreateHealthBar(model, maxHP)

	model.Parent = enemiesFolder
	enemiesAlive = enemiesAlive + 1

	-- Notify clients for spawn effect
	SpawnEffectEvent:FireAllClients(model.PrimaryPart.Position)

	-- Death handling
	humanoid.Died:Connect(function()
		clearEnemyHeldItem(model)
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
	local damageMultVal = data:FindFirstChild("DamageMultiplier")
	local difficultyDamageMult = damageMultVal and damageMultVal.Value or 1.0
	local dmg = math.floor(enemyDef.Damage * dmgMult * difficultyDamageMult)
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
					-- Skip if enemies are frozen
					if enemiesFrozen then
						continue
					end
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
							local baseWalkSpeedVal = data:FindFirstChild("BaseWalkSpeed")
							local engageDistanceVal = data:FindFirstChild("EngageDistance")
							local now = tick()
							local aggroRange = enemyDef.AggroRange or 28
							local attackRange = enemyDef.AttackRange or 4
							local engageDistance = engageDistanceVal and engageDistanceVal.Value or (attackRange + 4)
							local baseWalkSpeed = baseWalkSpeedVal and baseWalkSpeedVal.Value or humanoid.WalkSpeed
							local approachWalkSpeed = math.max(6, baseWalkSpeed * 0.55)

							-- Too far away: stay put until player is in aggro range.
							if dist > aggroRange then
								humanoid.WalkSpeed = baseWalkSpeed
								humanoid:MoveTo(enemy.PrimaryPart.Position)
								if aiState then aiState.Value = "approaching" end
								continue
							end

							-- APPROACHING STATE: slow approach with spacing, taunt mid-range.
							if aiState and aiState.Value == "approaching" then
								if hasFirstTaunted and not hasFirstTaunted.Value and dist <= math.min(25, aggroRange) and dist >= 10 then
									hasFirstTaunted.Value = true
									doEnemyTaunt(enemy, enemyDef, data)
									continue
								end

								if dist <= engageDistance then
									aiState.Value = "fighting"
								else
									humanoid.WalkSpeed = approachWalkSpeed
									humanoid:MoveTo(target.HumanoidRootPart.Position)
									continue
								end
							end

							-- FIGHTING STATE: limited crowding + staggered pressure.
							local nearbyFighters = countNearbyEnemies(target.HumanoidRootPart.Position, attackRange + 3, enemy)
							local maxActiveFighters = 2
							if nearbyFighters >= maxActiveFighters and dist > attackRange then
								humanoid.WalkSpeed = approachWalkSpeed
								humanoid:MoveTo(enemy.PrimaryPart.Position)
								continue
							end

							-- Check for taunt opportunity (higher chance: 50-70%)
							local lastTauntVal = data:FindFirstChild("LastTaunt")
							local tauntCooldown = enemyDef.TauntCooldown or 8
							local actualCooldown = math.max(4, tauntCooldown * 0.6)
							if lastTauntVal and (now - lastTauntVal.Value) >= actualCooldown then
								local tauntChance = math.max(0.5, (enemyDef.TauntChance or 0.3) * 2)
								if math.random() < tauntChance then
									doEnemyTaunt(enemy, enemyDef, data)
									continue
								end
							end

							if dist <= attackRange then
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
								humanoid.WalkSpeed = approachWalkSpeed
								humanoid:MoveTo(target.HumanoidRootPart.Position)
							end
						end
					end
				end
			end
		end
		task.wait(0.15)
	end
end

local function runEnemyLocomotion()
	while gameState == "Playing" do
		for _, enemy in ipairs(enemiesFolder:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart then
				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				local data = enemy:FindFirstChild("EnemyData")
				if humanoid and humanoid.Health > 0 and data then
					local taunting = data:FindFirstChild("IsTaunting")
					local comboStep = data:FindFirstChild("ComboStep")
					if (not taunting or not taunting.Value) and (not comboStep or comboStep.Value == 0) then
						local typeName = data:FindFirstChild("Type") and data.Type.Value or "Thug"
						local isMoving = humanoid.MoveDirection.Magnitude > 0.05
						AnimationManager.PlayEnemyLocomotion(enemy, typeName, isMoving)
					end
				end
			end
		end
		task.wait(0.1)
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

	local waveDef = EnemyTypes.GetWave(currentWave, currentSelectedLevel)
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
	groundItemsFolder:ClearAllChildren()
	for _, player in ipairs(Players:GetPlayers()) do
		clearHeldItem(player)
	end
	itemSpawnerRunning = false
	enemiesAlive = 0
	currentWave = 0
	totalScore = 0
	playerScores = {}
	playerDeaths = {}
	activeTeam = {}
end

local function checkAllPlayersDead()
	for _, player in ipairs(getActiveTeamPlayers()) do
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return false
			end
		end
	end
	return true
end

local function startGame(levelKey, difficultyKey)
	if gameState == "Playing" then return end

	currentSelectedLevel = resolveLevel(levelKey or currentSelectedLevel)
	currentSelectedDifficulty = resolveDifficulty(difficultyKey or currentSelectedDifficulty)
	currentDifficultySettings = DIFFICULTY_SETTINGS[currentSelectedDifficulty]

	cleanupGame()

	-- Build the arena for the selected level
	ArenaBuilder.Build(arenaFolder, currentSelectedLevel)

	gameState = "Playing"
	GameStateEvent:FireAllClients("GameStart", {
		level = currentSelectedLevel,
		levelName = EnemyTypes.GetLevel(currentSelectedLevel).DisplayName,
		difficulty = currentSelectedDifficulty,
	})

	-- Respawn all players at level-specific spawn
	local baseSpawnPos = ArenaBuilder.GetPlayerSpawn(currentSelectedLevel)
	local slotOffsets = {
		Vector3.new(-4, 0, 2),
		Vector3.new(4, 0, 2),
		Vector3.new(-4, 0, -2),
		Vector3.new(4, 0, -2),
	}
	activeTeam = {}
	local allPlayers = Players:GetPlayers()
	for index, player in ipairs(allPlayers) do
		if index > MAX_TEAM_PLAYERS then
			break
		end
		activeTeam[player.UserId] = true
	end
	for index, player in ipairs(getActiveTeamPlayers()) do
		player:LoadCharacter()
		playerDeaths[player.UserId] = false
		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			local slotOffset = slotOffsets[index] or Vector3.new((index - 1) * 3, 0, 0)
			local spawnPos = baseSpawnPos + slotOffset
			hrp.CFrame = CFrame.new(spawnPos, spawnPos + Vector3.new(0, 0, -1))
		end
	end

	task.wait(2)
	startNextWave()

	-- Start AI loop in separate thread
	task.spawn(runEnemyAI)
	task.spawn(runEnemyLocomotion)
	task.spawn(runGroundItemSpawner)
	spawnGroundItem()
end

local function endGame()
	gameState = "GameOver"
	GameStateEvent:FireAllClients("GameOver", totalScore)

	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		enemy:Destroy()
	end
	groundItemsFolder:ClearAllChildren()
	for _, player in ipairs(Players:GetPlayers()) do
		clearHeldItem(player)
	end
	itemSpawnerRunning = false
	enemiesAlive = 0
end

------------------------------------------------------------
-- ATTACK PROCESSING
------------------------------------------------------------
AttackEvent.OnServerEvent:Connect(function(player, attackType, targetPosition, attackDirection)
	if gameState ~= "Playing" then return end
	if not activeTeam[player.UserId] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	if heldItems[player.UserId] then return end

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
					Debris:AddItem(bv, 0.25)
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
				updateEnemyHealthBar(enemy, enemyHumanoid)
			end
		end
	end

	if hitSomething then
		totalScore = totalScore + CombatConfig.ScorePerHit
		ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
	end
end)

ItemInteractEvent.OnServerEvent:Connect(function(player, action, direction)
	if gameState ~= "Playing" then return end
	if not activeTeam[player.UserId] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if action == "Pickup" then
		if heldItems[player.UserId] then return end
		local nearestItem = findNearestGroundItem(player.Character.HumanoidRootPart.Position, CombatConfig.Items.PickupRange)
		if not nearestItem then return end

		local itemType = nearestItem:GetAttribute("ItemType")
		if itemType == "Health" then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + CombatConfig.Items.Health.HealAmount)
			nearestItem:Destroy()
			HeldItemStateEvent:FireClient(player, nil)
			return
		end

		local attachPart = player.Character:FindFirstChild("RightHand")
			or player.Character:FindFirstChild("Right Arm")
			or player.Character:FindFirstChild("HumanoidRootPart")
		if not attachPart then return end

		nearestItem.Anchored = false
		nearestItem.CanCollide = false
		nearestItem.Massless = true
		nearestItem.CFrame = attachPart.CFrame * CFrame.new(0, -0.8, -1)
		nearestItem.Parent = player.Character

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachPart
		weld.Part1 = nearestItem
		weld.Parent = nearestItem

		heldItems[player.UserId] = {
			Type = itemType,
			Part = nearestItem,
		}
		HeldItemStateEvent:FireClient(player, itemType)
	elseif action == "Use" then
		local held = heldItems[player.UserId]
		if not held or not held.Part or not held.Part.Parent then
			clearHeldItem(player)
			return
		end

		local now = tick()
		local lastUsed = itemUseCooldowns[player.UserId] or 0
		local useCooldown = CombatConfig.Items.Weapon.SwingCooldown
		if held.Type == "Rock" then
			useCooldown = CombatConfig.Items.Rock.ThrowCooldown
		end
		if now - lastUsed < useCooldown then
			return
		end
		itemUseCooldowns[player.UserId] = now

		if held.Type == "Weapon" then
			local didHit = tryMeleeItemSwing(
				player,
				CombatConfig.Items.Weapon.SwingDamage,
				CombatConfig.Items.Weapon.SwingRange,
				28
			)
			if didHit then
				totalScore = totalScore + CombatConfig.ScorePerHit
				ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
			end
		elseif held.Type == "Rock" then
			heldItems[player.UserId] = nil
			HeldItemStateEvent:FireClient(player, nil)
			throwRock(player, held.Part, direction)
		end
	elseif action == "Drop" then
		dropHeldItem(player, direction)
	elseif action == "Throw" then
		local held = heldItems[player.UserId]
		if not held or not held.Part or not held.Part.Parent then
			clearHeldItem(player)
			return
		end

		local now = tick()
		local lastUsed = itemUseCooldowns[player.UserId] or 0
		local throwCooldown = CombatConfig.Items.Rock.ThrowCooldown
		if held.Type == "Weapon" then
			throwCooldown = CombatConfig.Items.Weapon.ThrowCooldown
		end
		if now - lastUsed < throwCooldown then
			return
		end
		itemUseCooldowns[player.UserId] = now

		heldItems[player.UserId] = nil
		HeldItemStateEvent:FireClient(player, nil)
		if held.Type == "Weapon" then
			throwRock(player, held.Part, direction, CombatConfig.Items.Weapon, "WeaponThrow")
		else
			throwRock(player, held.Part, direction, CombatConfig.Items.Rock, "RockThrow")
		end
	end
end)

------------------------------------------------------------
-- PLAYER DEATH TRACKING
------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	refreshLobbyTeamStatus()
	player.CharacterAdded:Connect(function(character)
		clearHeldItem(player)

		local blockVal = Instance.new("BoolValue")
		blockVal.Name = "IsBlocking"
		blockVal.Value = false
		blockVal.Parent = character

		local dodgeVal = Instance.new("BoolValue")
		dodgeVal.Name = "IsDodging"
		dodgeVal.Value = false
		dodgeVal.Parent = character

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = CombatConfig.PlayerWalkSpeed
		humanoid.JumpPower = CombatConfig.PlayerJumpPower
		humanoid.Died:Connect(function()
			clearHeldItem(player)
			playerDeaths[player.UserId] = true
			PlayerDiedEvent:FireClient(player)

			task.wait(0.5)
			if gameState == "Playing" and activeTeam[player.UserId] and checkAllPlayersDead() then
				endGame()
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearHeldItem(player)
	activeTeam[player.UserId] = nil
	heldItems[player.UserId] = nil
	itemUseCooldowns[player.UserId] = nil
	refreshLobbyTeamStatus()
	if gameState == "Playing" and checkAllPlayersDead() then
		endGame()
	end
end)

RequestGameStartEvent.OnServerEvent:Connect(function(player, levelKey, difficultyKey)
	if gameState == "Lobby" then
		startGame(levelKey, difficultyKey)
	end
end)

-- Handle restart request
RequestRestartEvent.OnServerEvent:Connect(function(player)
	if gameState == "GameOver" then
		startGame(currentSelectedLevel, currentSelectedDifficulty)
	end
end)

-- Handle block state from client
BlockEvent.OnServerEvent:Connect(function(player, isBlocking)
	if gameState == "Playing" and not activeTeam[player.UserId] then return end
	if player.Character then
		local bv = player.Character:FindFirstChild("IsBlocking")
		if bv then
			bv.Value = isBlocking
		end
	end
end)

-- Handle dodge from client
DodgeEvent.OnServerEvent:Connect(function(player, direction)
	if gameState == "Playing" and not activeTeam[player.UserId] then return end
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
	Debris:AddItem(bv, 0.3)
end)

------------------------------------------------------------
-- DEV PANEL REMOTE EVENTS
------------------------------------------------------------
local DevFreezeEvent = createRemote("RemoteEvent", "DevFreezeEnemies")
local DevKillAllEvent = createRemote("RemoteEvent", "DevKillAll")
local DevSpawnEnemyEvent = createRemote("RemoteEvent", "DevSpawnEnemy")
local DevTriggerTauntEvent = createRemote("RemoteEvent", "DevTriggerTaunt")
local DevTriggerComboEvent = createRemote("RemoteEvent", "DevTriggerCombo")
local DevGodModeEvent = createRemote("RemoteEvent", "DevGodMode")
local DevSpawnWaveEvent = createRemote("RemoteEvent", "DevSpawnWave")
local DevPlayAnimEvent = createRemote("RemoteEvent", "DevPlayAnim")

local enemiesFrozen = false
local godModePlayers = {}

DevFreezeEvent.OnServerEvent:Connect(function(player)
	enemiesFrozen = not enemiesFrozen
	-- Stop/resume all enemy movement
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				if enemiesFrozen then
					humanoid.WalkSpeed = 0
					-- Set taunting to block AI actions
					local data = enemy:FindFirstChild("EnemyData")
					if data then
						local t = data:FindFirstChild("IsTaunting")
						if t then t.Value = true end
					end
				else
					local data = enemy:FindFirstChild("EnemyData")
					local baseWalkSpeed = data and data:FindFirstChild("BaseWalkSpeed")
					if baseWalkSpeed then
						humanoid.WalkSpeed = baseWalkSpeed.Value
					end
					if data then
						local t = data:FindFirstChild("IsTaunting")
						if t then t.Value = false end
					end
				end
			end
		end
	end
end)

DevKillAllEvent.OnServerEvent:Connect(function(player)
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end
	end
end)

DevSpawnEnemyEvent.OnServerEvent:Connect(function(player, typeName)
	if not EnemyTypes.Types[typeName] then return end
	local enemy = spawnEnemy(typeName, currentWave > 0 and currentWave or 1)
	if enemy then
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0 -- stands still
		end
		local data = enemy:FindFirstChild("EnemyData")
		if data then
			local t = data:FindFirstChild("IsTaunting")
			if t then t.Value = true end -- block AI
		end
	end
end)

local function findNearestEnemyToPlayer(player)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return nil end
	local pos = player.Character.HumanoidRootPart.Position
	local nearest, nearestDist = nil, math.huge
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local dist = (enemy.PrimaryPart.Position - pos).Magnitude
				if dist < nearestDist then
					nearest = enemy
					nearestDist = dist
				end
			end
		end
	end
	return nearest
end

DevTriggerTauntEvent.OnServerEvent:Connect(function(player)
	local enemy = findNearestEnemyToPlayer(player)
	if not enemy then return end
	local data = enemy:FindFirstChild("EnemyData")
	if not data then return end
	local typeName = data:FindFirstChild("Type") and data.Type.Value or "Thug"
	local enemyDef = EnemyTypes.Types[typeName]
	if enemyDef then
		doEnemyTaunt(enemy, enemyDef, data)
	end
end)

DevTriggerComboEvent.OnServerEvent:Connect(function(player)
	local enemy = findNearestEnemyToPlayer(player)
	if not enemy then return end
	local data = enemy:FindFirstChild("EnemyData")
	if not data then return end
	local typeName = data:FindFirstChild("Type") and data.Type.Value or "Thug"
	local enemyDef = EnemyTypes.Types[typeName]
	if not enemyDef then return end
	local target = player.Character
	if not target then return end
	local comboHits = enemyDef.ComboHits or 1
	for i = 1, comboHits do
		task.delay((i - 1) * (enemyDef.ComboCooldown or 0.5), function()
			doEnemyComboHit(enemy, enemyDef, data, target, i)
		end)
	end
end)

DevGodModeEvent.OnServerEvent:Connect(function(player)
	godModePlayers[player.UserId] = not godModePlayers[player.UserId]
end)

DevSpawnWaveEvent.OnServerEvent:Connect(function(player)
	if gameState == "Playing" then
		-- Kill remaining enemies first
		for _, enemy in ipairs(enemiesFolder:GetChildren()) do
			if enemy:IsA("Model") then
				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				if humanoid then humanoid.Health = 0 end
			end
		end
	elseif gameState ~= "Playing" then
		-- Force start game
		gameState = "Playing"
		startNextWave()
		task.spawn(runEnemyAI)
		task.spawn(runEnemyLocomotion)
	end
end)

-- Patch damage to respect god mode
local originalTakeDamage = nil -- We'll intercept via the DamageEvent response

-- Override: check god mode in enemy AI combat
local _origRunEnemyAI = runEnemyAI
-- We intercept god mode by checking in the humanoid health changed
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(char)
		local humanoid = char:WaitForChild("Humanoid")
		local lastHealth = humanoid.MaxHealth
		humanoid.HealthChanged:Connect(function(newHealth)
			if godModePlayers[p.UserId] and newHealth < lastHealth then
				humanoid.Health = humanoid.MaxHealth
			end
			lastHealth = newHealth
		end)
	end)
end)

-- Also handle frozen enemies in the AI loop by patching
local origRunEnemyAI = runEnemyAI

------------------------------------------------------------
-- INIT
------------------------------------------------------------
ArenaBuilder.Build(arenaFolder, currentSelectedLevel)
refreshLobbyTeamStatus()
print("[BrawlAlley] Arena built. Waiting for players...")
