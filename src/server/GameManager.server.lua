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
local StateMachine = require(Shared:WaitForChild("RuntimeStateMachine"))
local CharacterStates = require(Shared:WaitForChild("CharacterStates"))
local ArenaBuilder = require(script.Parent:WaitForChild("ArenaBuilder"))

-- Create RemoteEvents for client-server communication
local function createRemote(className, name)
	local remotesFolder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotesFolder then
		local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
		if not sharedFolder then
			sharedFolder = Instance.new("Folder")
			sharedFolder.Name = "Shared"
			sharedFolder.Parent = ReplicatedStorage
		end
		remotesFolder = sharedFolder:FindFirstChild("Remotes")
		if not remotesFolder then
			remotesFolder = Instance.new("Folder")
			remotesFolder.Name = "Remotes"
			remotesFolder.Parent = sharedFolder
		end
	end

	local existing = remotesFolder:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
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
local StaminaBoostEvent = createRemote("RemoteEvent", "StaminaBoost")
local BlockEvent = createRemote("RemoteEvent", "BlockEvent")
local DodgeEvent = createRemote("RemoteEvent", "DodgeEvent")
local GrabEvent = createRemote("RemoteEvent", "GrabEvent")
local TeamStatusEvent = createRemote("RemoteEvent", "TeamStatusEvent")
local MoneyEvent = createRemote("RemoteEvent", "MoneyEvent")
local ShopPurchaseEvent = createRemote("RemoteEvent", "ShopPurchase")
local ShopResultEvent = createRemote("RemoteEvent", "ShopResult")

-- Game state
local gameState = "Lobby" -- Lobby, Playing, GameOver
local currentWave = 0
local enemiesAlive = 0
local totalScore = 0 -- shared score for co-op
local playerScores = {} -- per-player scores
local playerMoney = {} -- per-player money
local playerDeaths = {} -- track dead players
local playerShield = {}
local heldItems = {}
local playerInventories = {}
local itemUseCooldowns = {}
local grabUseCooldowns = {}
local itemSpawnerRunning = false
local enemyHeldItems = setmetatable({}, { __mode = "k" })
local enemyMoveAnimTimes = setmetatable({}, { __mode = "k" })
local enemyStateMachines = setmetatable({}, { __mode = "k" })
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

local function getMoneyConfig()
	return CombatConfig.Money or {}
end

local function awardMoney(player, amount, reason)
	if not player or amount == nil or amount == 0 then
		return
	end
	local uid = player.UserId
	playerMoney[uid] = (playerMoney[uid] or 0) + amount
	MoneyEvent:FireClient(player, playerMoney[uid], amount, reason or "Reward")
end

local function setMoney(player, value)
	if not player then return end
	playerMoney[player.UserId] = value or 0
	MoneyEvent:FireClient(player, playerMoney[player.UserId], 0, "Sync")
end

local function getInventory(player)
	if not player then
		return nil
	end
	local uid = player.UserId
	local inventory = playerInventories[uid]
	if not inventory then
		inventory = {
			slots = {nil, nil, nil},
			equippedSlot = 1,
		}
		playerInventories[uid] = inventory
	end
	return inventory
end

local function getEquippedItemType(player)
	local inventory = getInventory(player)
	if not inventory then
		return nil
	end
	return inventory.slots[inventory.equippedSlot]
end

local function sendInventoryState(player)
	local inventory = getInventory(player)
	if not inventory then
		HeldItemStateEvent:FireClient(player, nil)
		return
	end
	HeldItemStateEvent:FireClient(player, {
		equipped = inventory.slots[inventory.equippedSlot],
		slots = {inventory.slots[1], inventory.slots[2], inventory.slots[3]},
		equippedSlot = inventory.equippedSlot,
	})
end

local function getMoney(player)
	if not player then return 0 end
	return playerMoney[player.UserId] or 0
end

local function trySpendMoney(player, amount, reason)
	if not player then
		return false
	end
	if amount <= 0 then
		return true
	end
	local current = getMoney(player)
	if current < amount then
		return false
	end
	playerMoney[player.UserId] = current - amount
	MoneyEvent:FireClient(player, playerMoney[player.UserId], -amount, reason or "Spend")
	return true
end

local function tagEnemyLastHit(enemy, player)
	if not enemy or not player then
		return
	end
	enemy:SetAttribute("LastHitPlayerUserId", player.UserId)
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

local function createItemPart(itemType)
	local item = Instance.new("Part")
	item.Name = itemType .. "Item"
	item.Anchored = true
	item.CanCollide = true
	item:SetAttribute("ItemType", itemType)
	item:SetAttribute("IsGroundItem", true)

	if itemType == "Health" then
		item.Size = Vector3.new(2, 2, 2)
		item.Shape = Enum.PartType.Ball
		item.BrickColor = BrickColor.new("Lime green")
		item.Material = Enum.Material.Neon
	elseif itemType == "Weapon" or itemType == "Sword" then
		item.Size = Vector3.new(1, 3, 1)
		item.BrickColor = itemType == "Sword" and BrickColor.new("Institutional white") or BrickColor.new("Really black")
		item.Material = Enum.Material.Metal
	elseif itemType == "Pistol" then
		item.Size = Vector3.new(0.34, 0.56, 1.18)
		item.BrickColor = BrickColor.new("Black")
		item.Material = Enum.Material.Metal
		item.Color = Color3.fromRGB(35, 35, 38)

		local slide = Instance.new("Part")
		slide.Name = "Slide"
		slide.Size = Vector3.new(0.3, 0.18, 0.72)
		slide.Color = Color3.fromRGB(90, 90, 96)
		slide.Material = Enum.Material.Metal
		slide.Anchored = false
		slide.CanCollide = false
		slide.Massless = true
		slide.CFrame = item.CFrame * CFrame.new(0, 0.16, -0.06)
		slide.Parent = item

		local slideWeld = Instance.new("WeldConstraint")
		slideWeld.Part0 = item
		slideWeld.Part1 = slide
		slideWeld.Parent = slide

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.26, 0.72, 0.26)
		handle.Color = Color3.fromRGB(62, 42, 30)
		handle.Material = Enum.Material.SmoothPlastic
		handle.Anchored = false
		handle.CanCollide = false
		handle.Massless = true
		handle.CFrame = item.CFrame * CFrame.new(0, -0.48, 0.24) * CFrame.Angles(math.rad(-18), 0, 0)
		handle.Parent = item

		local handleWeld = Instance.new("WeldConstraint")
		handleWeld.Part0 = item
		handleWeld.Part1 = handle
		handleWeld.Parent = handle

		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(0.14, 0.14, 0.34)
		barrel.Color = Color3.fromRGB(120, 120, 125)
		barrel.Material = Enum.Material.Metal
		barrel.Anchored = false
		barrel.CanCollide = false
		barrel.Massless = true
		barrel.CFrame = item.CFrame * CFrame.new(0, 0, -0.74)
		barrel.Parent = item

		local barrelWeld = Instance.new("WeldConstraint")
		barrelWeld.Part0 = item
		barrelWeld.Part1 = barrel
		barrelWeld.Parent = barrel

		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = Vector3.new(0, 0.02, -0.78)
		muzzle.Parent = item
	else
		item.Size = Vector3.new(2.5, 2.5, 2.5)
		item.Shape = Enum.PartType.Ball
		item.BrickColor = BrickColor.new("Dark stone grey")
		item.Material = Enum.Material.Slate
	end

	return item
end

local function getHeldGripOffset(itemType, attachPart)
	local partName = attachPart and attachPart.Name or ""
	if itemType == "Pistol" then
		if partName == "RightHand" then
			return CFrame.new(-0.02, -0.04, -0.64) * CFrame.Angles(math.rad(-96), math.rad(-10), math.rad(-8))
		end
		return CFrame.new(-0.06, -0.92, -0.44) * CFrame.Angles(math.rad(-96), math.rad(-10), math.rad(-8))
	end
	return CFrame.new(0, -0.8, -1)
end

local function createGroundItem(itemType)
	local item = createItemPart(itemType)
	item.Position = getRandomGroundItemPos()

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
	elseif roll < 0.52 then
		return "Weapon"
	elseif roll < 0.72 then
		return "Sword"
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
end

local function refreshEquippedVisual(player)
	if not player or not player.Character then
		return false
	end

	clearHeldItem(player)

	local itemType = getEquippedItemType(player)
	if not itemType then
		sendInventoryState(player)
		return true
	end

	local attachPart = player.Character:FindFirstChild("RightHand")
		or player.Character:FindFirstChild("Right Arm")
		or player.Character:FindFirstChild("HumanoidRootPart")
	if not attachPart then
		sendInventoryState(player)
		return false
	end

	local itemPart = createItemPart(itemType)
	itemPart.Anchored = false
	itemPart.CanCollide = false
	itemPart.Massless = true
	itemPart.CFrame = attachPart.CFrame * getHeldGripOffset(itemType, attachPart)
	itemPart.Parent = player.Character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = itemPart
	weld.Parent = itemPart

	heldItems[player.UserId] = {
		Type = itemType,
		Part = itemPart,
	}
	sendInventoryState(player)
	return true
end

local function setEquippedSlot(player, slotIndex)
	local inventory = getInventory(player)
	if not inventory then
		return false
	end
	if typeof(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 3 then
		return false
	end
	inventory.equippedSlot = slotIndex
	refreshEquippedVisual(player)
	return true
end

local function addInventoryItem(player, itemType)
	local inventory = getInventory(player)
	if not inventory then
		return false
	end

	local emptySlot = nil
	for i = 1, 3 do
		if inventory.slots[i] == nil then
			emptySlot = i
			break
		end
	end
	if not emptySlot then
		sendInventoryState(player)
		return false
	end

	inventory.slots[emptySlot] = itemType
	if not inventory.slots[inventory.equippedSlot] then
		inventory.equippedSlot = emptySlot
	end
	refreshEquippedVisual(player)
	return true
end

local function dropHeldItem(player, dropDirection)
	local inventory = getInventory(player)
	if not inventory then
		return
	end

	local equippedSlot = inventory.equippedSlot
	local equippedType = inventory.slots[equippedSlot]
	local held = heldItems[player.UserId]
	if not held or not held.Part or not held.Part.Parent then
		inventory.slots[equippedSlot] = nil
		refreshEquippedVisual(player)
		return
	end

	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		held.Part:Destroy()
		inventory.slots[equippedSlot] = nil
		refreshEquippedVisual(player)
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
	held.Part:SetAttribute("ItemType", equippedType or held.Type)
	held.Part:SetAttribute("IsGroundItem", true)

	clearHeldItem(player)
	inventory.slots[equippedSlot] = nil
	itemUseCooldowns[player.UserId] = nil
	refreshEquippedVisual(player)
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
	nearestItem.CFrame = attachPart.CFrame * getHeldGripOffset(itemType, attachPart)
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

local function captureAndDisableCollisions(model)
	local snapshot = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(snapshot, {
				part = desc,
				canCollide = desc.CanCollide,
				massless = desc.Massless,
			})
			desc.CanCollide = false
			desc.Massless = true
		end
	end
	return snapshot
end

local function restoreCollisionSnapshot(snapshot)
	for _, info in ipairs(snapshot) do
		local part = info.part
		if part and part.Parent then
			part.CanCollide = info.canCollide
			part.Massless = info.massless
		end
	end
end

local function findSuplexTarget(player, requestedEnemy)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	local hrp = player.Character.HumanoidRootPart
	local grabConfig = CombatConfig.Grab or {}
	local maxRange = grabConfig.Range or 7
	local facing = hrp.CFrame.LookVector
	local bestEnemy = nil
	local bestDist = maxRange + 0.001

	local function tryCandidate(enemy)
		if not enemy or enemy.Parent ~= enemiesFolder or not enemy.PrimaryPart then
			return
		end
		local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
		if not enemyHumanoid or enemyHumanoid.Health <= 0 then
			return
		end
		local delta = enemy.PrimaryPart.Position - hrp.Position
		local dist = delta.Magnitude
		if dist > maxRange or dist >= bestDist then
			return
		end
		local dot = dist > 0 and delta.Unit:Dot(facing) or 1
		if dot <= 0.2 then
			return
		end
		bestEnemy = enemy
		bestDist = dist
	end

	if requestedEnemy and requestedEnemy:IsA("Model") then
		tryCandidate(requestedEnemy)
	end
	for _, enemy in ipairs(Utils.GetEnemiesInRange(hrp.Position, maxRange, enemiesFolder)) do
		if enemy ~= requestedEnemy then
			tryCandidate(enemy)
		end
	end

	return bestEnemy, facing
end

local function doSuplex(player, enemy, facing)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	if not enemy or enemy.Parent ~= enemiesFolder or not enemy.PrimaryPart then
		return false
	end

	local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not enemyHumanoid or enemyHumanoid.Health <= 0 then
		return false
	end

	local hrp = player.Character.HumanoidRootPart
	local grabConfig = CombatConfig.Grab or {}
	local grabOffset = grabConfig.GrabOffset or 2.2
	local slamDamage = grabConfig.Damage or 24
	local slamKnockback = grabConfig.SlamKnockbackForce or 36
	local forward = (facing and facing.Magnitude > 0) and facing.Unit or hrp.CFrame.LookVector
	local enemyRoot = enemy.PrimaryPart
	local collisionSnapshot = captureAndDisableCollisions(enemy)
	local previousPlatformStand = enemyHumanoid.PlatformStand
	local previousAutoRotate = enemyHumanoid.AutoRotate
	local released = false

	local function releaseEnemy()
		if released then
			return
		end
		released = true
		if enemyRoot and enemyRoot.Parent then
			enemyRoot.Anchored = false
			enemyRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			enemyRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end
		if enemyHumanoid and enemyHumanoid.Parent then
			enemyHumanoid.PlatformStand = previousPlatformStand
			enemyHumanoid.AutoRotate = previousAutoRotate
		end
		restoreCollisionSnapshot(collisionSnapshot)
	end

	enemyRoot.Anchored = true
	enemyHumanoid.PlatformStand = true
	enemyHumanoid.AutoRotate = false
	local grabPos = hrp.Position + forward * math.max(0.8, grabOffset - 0.5) + Vector3.new(0, 1.05, 0)
	enemyRoot.CFrame = CFrame.new(grabPos, hrp.Position + Vector3.new(0, 1.05, 0)) * CFrame.Angles(-math.rad(38), 0, 0)
	enemyRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	enemyRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	local esm = enemyStateMachines[enemy]
	if esm then
		esm:SetState("HitStun", true)
	end

	task.delay(0.12, function()
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			releaseEnemy()
			return
		end
		if not enemyRoot.Parent or not enemyHumanoid.Parent then
			releaseEnemy()
			return
		end

		local currentRoot = player.Character:FindFirstChild("HumanoidRootPart")
		if not currentRoot then
			releaseEnemy()
			return
		end
		local liftPos = currentRoot.Position + forward * 0.15 + Vector3.new(0, 3.25, 0)
		enemyRoot.CFrame = CFrame.new(liftPos, liftPos - forward) * CFrame.Angles(-math.rad(96), 0, 0)
		enemyRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		enemyRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

		task.delay(0.14, function()
			if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
				releaseEnemy()
				return
			end
			if not enemyRoot.Parent or not enemyHumanoid.Parent then
				releaseEnemy()
				return
			end

			local slamRoot = player.Character:FindFirstChild("HumanoidRootPart")
			if not slamRoot then
				releaseEnemy()
				return
			end

			local slamPos = slamRoot.Position - forward * (grabOffset - 0.1) + Vector3.new(0, 1.0, 0)
			enemyRoot.CFrame = CFrame.new(slamPos, slamPos - forward) * CFrame.Angles(math.rad(100), 0, 0)
			enemyRoot.Anchored = false
			enemyRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			enemyRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

			if enemyHumanoid.Health > 0 then
				enemyHumanoid:TakeDamage(slamDamage)
				tagEnemyLastHit(enemy, player)
				local hitReward = getMoneyConfig().HitReward or 0
				if hitReward > 0 then
					awardMoney(player, hitReward, "Hit")
				end
				updateEnemyHealthBar(enemy, enemyHumanoid)
				applyEnemyKnockback(enemy, -forward * slamKnockback, 5, 0.25)
				ComicBubbleEvent:FireAllClients(enemy, "heavy", enemy.PrimaryPart.Position)
				EnemyHitEvent:FireAllClients(enemy, "hit", slamRoot.Position, "Suplex")
				totalScore = totalScore + CombatConfig.ScorePerHit
				ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
			end

			task.delay(0.18, releaseEnemy)
		end)
	end)

	-- Failsafe so enemy never stays collisionless/anchored on interruption.
	task.delay(0.8, releaseEnemy)

	return true
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
				tagEnemyLastHit(enemy, player)
				local hitReward = getMoneyConfig().HitReward or 0
				if hitReward > 0 then
					awardMoney(player, hitReward, "Hit")
				end
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

local function emitPistolMuzzleEffects(heldPart)
	if not heldPart or not heldPart.Parent then
		return
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "MuzzleSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Lifetime = NumberRange.new(0.15, 0.28)
	smoke.Speed = NumberRange.new(3, 6)
	smoke.Rate = 0
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.RotSpeed = NumberRange.new(-60, 60)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(210, 210, 210), Color3.fromRGB(120, 120, 120))
	smoke.Parent = heldPart
	smoke:Emit(7)
	Debris:AddItem(smoke, 0.35)

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 210, 140)
	flash.Range = 8
	flash.Brightness = 2.2
	flash.Parent = heldPart
	Debris:AddItem(flash, 0.06)
end

local function createShotTracer(origin, targetPos)
	local distance = (targetPos - origin).Magnitude
	if distance <= 0.05 then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Name = "PistolTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 235, 160)
	tracer.Transparency = 0.2
	tracer.Size = Vector3.new(0.08, 0.08, distance)
	tracer.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -distance * 0.5)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.05)
end

local function fireHitscanPistol(player, aimDirection, pistolConfig)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local character = player.Character
	local hrp = character.HumanoidRootPart
	local head = character:FindFirstChild("Head")
	local held = heldItems[player.UserId]
	local dir = (aimDirection and aimDirection.Magnitude > 0) and aimDirection.Unit or hrp.CFrame.LookVector
	local maxRange = pistolConfig.MaxRange or 140
	local aimOrigin = head and head.Position or (hrp.Position + Vector3.new(0, 1.5, 0))

	local centerParams = RaycastParams.new()
	centerParams.FilterType = Enum.RaycastFilterType.Exclude
	centerParams.FilterDescendantsInstances = {character}
	centerParams.IgnoreWater = true

	local centerResult = workspace:Raycast(aimOrigin, dir * maxRange, centerParams)
	local targetPos = centerResult and centerResult.Position or (aimOrigin + dir * maxRange)

	local muzzlePos = aimOrigin + dir * 0.8
	if held and held.Part and held.Part.Parent then
		local muzzle = held.Part:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			muzzlePos = muzzle.WorldPosition
		end
		emitPistolMuzzleEffects(held.Part)
	end

	local muzzleDir = targetPos - muzzlePos
	if muzzleDir.Magnitude < 0.05 then
		muzzleDir = dir
	else
		muzzleDir = muzzleDir.Unit
	end

	local shotParams = RaycastParams.new()
	shotParams.FilterType = Enum.RaycastFilterType.Exclude
	shotParams.FilterDescendantsInstances = {character}
	shotParams.IgnoreWater = true

	local shotDistance = math.min(maxRange, (targetPos - muzzlePos).Magnitude + 1)
	local shotResult = workspace:Raycast(muzzlePos, muzzleDir * shotDistance, shotParams)
	local visualEnd = shotResult and shotResult.Position or (muzzlePos + muzzleDir * shotDistance)
	createShotTracer(muzzlePos, visualEnd)

	if not shotResult then
		return
	end

	local enemy = shotResult.Instance and shotResult.Instance:FindFirstAncestorOfClass("Model")
	if not enemy or enemy.Parent ~= enemiesFolder then
		return
	end
	local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not enemyHumanoid or enemyHumanoid.Health <= 0 then
		return
	end

	enemyHumanoid:TakeDamage(pistolConfig.ShotDamage or 15)
	tagEnemyLastHit(enemy, player)
	local hitReward = getMoneyConfig().HitReward or 0
	if hitReward > 0 then
		awardMoney(player, hitReward, "Hit")
	end
	totalScore = totalScore + CombatConfig.ScorePerHit
	ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
	updateEnemyHealthBar(enemy, enemyHumanoid)
	EnemyHitEvent:FireAllClients(enemy, "hit", shotResult.Position, "PistolShot")
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
		tagEnemyLastHit(enemy, player)
		local hitReward = getMoneyConfig().HitReward or 0
		if hitReward > 0 then
			awardMoney(player, hitReward, "Hit")
		end
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

local function stabilizeEnemyInArena(enemy, humanoid)
	if not enemy or not enemy.PrimaryPart or not humanoid then
		return
	end

	local root = enemy.PrimaryPart
	local currentPos = root.Position
	local clampedPos = ArenaBuilder.ClampToPlayableArea(currentPos, currentSelectedLevel)
	local outOfBounds = math.abs(clampedPos.X - currentPos.X) > 0.01 or math.abs(clampedPos.Z - currentPos.Z) > 0.01
	local tooHigh = currentPos.Y > 30
	local tooLow = currentPos.Y < -20
	local needsRecovery = outOfBounds or tooHigh or tooLow

	if needsRecovery then
		local safePos = Vector3.new(clampedPos.X, 3, clampedPos.Z)
		enemy:PivotTo(CFrame.new(safePos))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
		return
	end

	-- Prevent random extreme launches from stacking impulses.
	local v = root.AssemblyLinearVelocity
	if v.Y > 35 then
		root.AssemblyLinearVelocity = Vector3.new(v.X, 20, v.Z)
	end
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

	local safeSpawnPos = ArenaBuilder.ClampToPlayableArea(spawnPos, currentSelectedLevel)
	model:PivotTo(CFrame.new(safeSpawnPos))

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(("[GameManager] Enemy '%s' spawned as %s, expected R15"):format(
			enemyDef.Name,
			tostring(humanoid.RigType)
		))
	end
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

	-- Create state machine for this enemy
	local sm = StateMachine.new(model, CharacterStates.Enemy)
	sm:SetData("enemyType", typeName)
	sm:SetState("Idle", true)
	enemyStateMachines[model] = sm

	model.Parent = enemiesFolder
	enemiesAlive = enemiesAlive + 1

	-- Notify clients for spawn effect
	SpawnEffectEvent:FireAllClients(model.PrimaryPart.Position)

	-- Death handling
	humanoid.Died:Connect(function()
		local esm = enemyStateMachines[model]
		if esm then esm:Kill() end
		clearEnemyHeldItem(model)
		enemiesAlive = enemiesAlive - 1

		local killerUserId = model:GetAttribute("LastHitPlayerUserId")
		if killerUserId then
			local killerPlayer = Players:GetPlayerByUserId(killerUserId)
			local killReward = getMoneyConfig().KillReward or 25
			if killerPlayer and killReward > 0 then
				awardMoney(killerPlayer, killReward, "Kill")
			end
		end

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

	local sm = enemyStateMachines[enemy]
	if sm then sm:SetState("Taunting", true) end

	local typeName = data.Type.Value
	EnemyAnimEvent:FireAllClients(enemy, "taunt", typeName)

	if typeName == "Thug" then
		AnimationManager.PlayThugTaunt(enemy)
	elseif typeName == "Brawler" then
		AnimationManager.PlayBrawlerTaunt(enemy)
	elseif typeName == "Speedster" then
		AnimationManager.PlaySpeedsterTaunt(enemy)
	end

	AnimationManager.ShowTauntText(enemy, enemyDef.TauntText, 2)

	local lastTauntVal = data:FindFirstChild("LastTaunt")
	if lastTauntVal then lastTauntVal.Value = tick() end

	local tauntDuration = (typeName == "Brawler") and 1.8 or 1.2
	task.delay(tauntDuration, function()
		if taunting and taunting.Parent then
			taunting.Value = false
		end
		if sm and sm:GetState() == "Taunting" then
			sm:Unlock()
			sm:SetState("Idle", true)
		end
	end)
end

local function doEnemyComboHit(enemy, enemyDef, data, target, hitIndex)
	local typeName = data.Type.Value
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot or not enemy.PrimaryPart then return false end

	local hitCommitRange = math.max(2.5, (enemyDef.AttackRange or 4) * 0.72)
	if (enemy.PrimaryPart.Position - targetRoot.Position).Magnitude > hitCommitRange then
		return false
	end

	local sm = enemyStateMachines[enemy]
	if sm then sm:SetState("Attacking", true) end

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
	local hitPlayer = Players:GetPlayerFromCharacter(target)
	local shieldLeft = hitPlayer and (playerShield[hitPlayer.UserId] or 0) or 0
	if hitPlayer and shieldLeft > 0 then
		local absorbed = math.min(shieldLeft, dmg)
		playerShield[hitPlayer.UserId] = shieldLeft - absorbed
		dmg = math.max(0, dmg - absorbed)
	end
	targetHumanoid:TakeDamage(dmg)

	-- Notify hit player
	if hitPlayer then
		DamageEvent:FireClient(hitPlayer, dmg, isBlocking, enemy.PrimaryPart.Position)
		if dmgMult >= 1.3 then
			ScreenShakeEvent:FireClient(hitPlayer, dmgMult * 5, 0.3)
		end
	end

	-- Visual feedback
	EnemyHitEvent:FireAllClients(enemy, "attack")
	return true
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
					stabilizeEnemyInArena(enemy, humanoid)

					-- Skip if enemies are frozen
					if enemiesFrozen then
						continue
					end
					-- Skip if state machine is locked (HitStun, Attacking, Taunting)
					local sm = enemyStateMachines[enemy]
					if sm and sm:IsLocked() then
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
							local attackCommitRange = math.max(2.5, attackRange * 0.72)
							local engageDistance = engageDistanceVal and engageDistanceVal.Value or (attackRange + 4)
							local baseWalkSpeed = baseWalkSpeedVal and baseWalkSpeedVal.Value or humanoid.WalkSpeed
							local approachWalkSpeed = math.max(6, baseWalkSpeed * 0.55)

							-- Too far away: stay put until player is in aggro range.
							if dist > aggroRange then
								humanoid.WalkSpeed = baseWalkSpeed
								humanoid:MoveTo(enemy.PrimaryPart.Position)
								if aiState then aiState.Value = "approaching" end
								local sm = enemyStateMachines[enemy]
								if sm and sm:GetState() ~= "Idle" then sm:SetState("Idle") end
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
									local sm = enemyStateMachines[enemy]
									if sm and sm:GetState() ~= "Walking" then sm:SetState("Walking") end
									continue
								end
							end

							-- FIGHTING STATE: limited crowding + staggered pressure.
							local nearbyFighters = countNearbyEnemies(target.HumanoidRootPart.Position, attackRange + 3, enemy)
							local maxActiveFighters = 2
							if nearbyFighters >= maxActiveFighters and dist > attackCommitRange then
								humanoid.WalkSpeed = approachWalkSpeed
								humanoid:MoveTo(enemy.PrimaryPart.Position)
								local sm = enemyStateMachines[enemy]
								if sm and sm:GetState() ~= "Idle" then sm:SetState("Idle") end
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

							if dist <= attackCommitRange then
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
												if doEnemyComboHit(enemy, enemyDef, data, target, currentStep) then
													comboStepVal.Value = currentStep
													lastComboVal.Value = now
												else
													comboStepVal.Value = 0
												end
											end
										end
									elseif currentStep == 0 and (now - lastAtk.Value) >= enemyDef.AttackCooldown then
										if doEnemyComboHit(enemy, enemyDef, data, target, 1) then
											comboStepVal.Value = 1
											if lastComboVal then lastComboVal.Value = now end
											lastAtk.Value = now
										end
									else
										if currentStep > 0 and lastComboVal and (now - lastComboVal.Value) >= comboCooldown + 0.3 then
											comboStepVal.Value = 0
										end
									end
								end
							else
								humanoid.WalkSpeed = approachWalkSpeed
								humanoid:MoveTo(target.HumanoidRootPart.Position)
								local sm = enemyStateMachines[enemy]
								if sm and sm:GetState() ~= "Walking" then sm:SetState("Walking") end
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
		local dt = 0.1
		for _, enemy in ipairs(enemiesFolder:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart then
				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local sm = enemyStateMachines[enemy]
					if sm then
						sm:Update(dt)
					end
				end
			end
		end
		task.wait(dt)
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
	playerMoney = {}
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
		setMoney(player, 0)
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
				tagEnemyLastHit(enemy, player)
				local hitReward = getMoneyConfig().HitReward or 0
				if hitReward > 0 then
					awardMoney(player, hitReward, "Hit")
				end
				hitSomething = true

				-- Set HitStun state on enemy
				local esm = enemyStateMachines[enemy]
				if esm then esm:SetState("HitStun", true) end

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

GrabEvent.OnServerEvent:Connect(function(player, requestedEnemy)
	if gameState ~= "Playing" then return end
	if not activeTeam[player.UserId] then return end
	if heldItems[player.UserId] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local now = tick()
	local cooldown = (CombatConfig.Grab and CombatConfig.Grab.Cooldown) or 1.25
	if now - (grabUseCooldowns[player.UserId] or 0) < cooldown then
		return
	end

	local targetEnemy, facing = findSuplexTarget(player, requestedEnemy)
	if not targetEnemy then
		return
	end

	grabUseCooldowns[player.UserId] = now
	local blockVal = player.Character:FindFirstChild("IsBlocking")
	if blockVal then
		blockVal.Value = false
	end
	doSuplex(player, targetEnemy, facing)
end)

ItemInteractEvent.OnServerEvent:Connect(function(player, action, direction)
	if gameState ~= "Playing" then return end
	if not activeTeam[player.UserId] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if action == "Pickup" then
		local nearestItem = findNearestGroundItem(player.Character.HumanoidRootPart.Position, CombatConfig.Items.PickupRange)
		if not nearestItem then return end

		local itemType = nearestItem:GetAttribute("ItemType")
		if itemType == "Health" then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + CombatConfig.Items.Health.HealAmount)
			nearestItem:Destroy()
			sendInventoryState(player)
			return
		end
		if addInventoryItem(player, itemType) then
			nearestItem:Destroy()
		end
	elseif action == "Use" then
		local held = heldItems[player.UserId]
		if not held or not held.Part or not held.Part.Parent then
			refreshEquippedVisual(player)
			return
		end

		local now = tick()
		local lastUsed = itemUseCooldowns[player.UserId] or 0
		local useCooldown = CombatConfig.Items.Weapon.SwingCooldown
		if held.Type == "Rock" then
			useCooldown = CombatConfig.Items.Rock.ThrowCooldown
		elseif held.Type == "Sword" then
			useCooldown = CombatConfig.Items.Sword.SwingCooldown
		elseif held.Type == "Pistol" then
			useCooldown = CombatConfig.Items.Pistol.ShotCooldown
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
		elseif held.Type == "Sword" then
			local didHit = tryMeleeItemSwing(
				player,
				CombatConfig.Items.Sword.SwingDamage,
				CombatConfig.Items.Sword.SwingRange,
				CombatConfig.Items.Sword.KnockbackForce
			)
			if didHit then
				totalScore = totalScore + CombatConfig.ScorePerHit
				ScoreEvent:FireAllClients("hit", CombatConfig.ScorePerHit, totalScore)
			end
		elseif held.Type == "Pistol" then
			fireHitscanPistol(player, direction, CombatConfig.Items.Pistol)
		elseif held.Type == "Rock" then
			local inventory = getInventory(player)
			inventory.slots[inventory.equippedSlot] = nil
			clearHeldItem(player)
			sendInventoryState(player)
			throwRock(player, held.Part, direction)
		end
	elseif action == "Drop" then
		dropHeldItem(player, direction)
	elseif action == "Throw" then
		local held = heldItems[player.UserId]
		if not held or not held.Part or not held.Part.Parent then
			refreshEquippedVisual(player)
			return
		end

		local now = tick()
		local lastUsed = itemUseCooldowns[player.UserId] or 0
		local throwCooldown = CombatConfig.Items.Rock.ThrowCooldown
		if held.Type == "Weapon" then
			throwCooldown = CombatConfig.Items.Weapon.ThrowCooldown
		elseif held.Type == "Sword" then
			throwCooldown = CombatConfig.Items.Sword.ThrowCooldown
		elseif held.Type == "Pistol" then
			throwCooldown = CombatConfig.Items.Pistol.ShotCooldown
		end
		if now - lastUsed < throwCooldown then
			return
		end
		itemUseCooldowns[player.UserId] = now

		local inventory = getInventory(player)
		inventory.slots[inventory.equippedSlot] = nil
		clearHeldItem(player)
		sendInventoryState(player)
		if held.Type == "Weapon" then
			throwRock(player, held.Part, direction, CombatConfig.Items.Weapon, "WeaponThrow")
		elseif held.Type == "Sword" then
			throwRock(player, held.Part, direction, CombatConfig.Items.Sword, "SwordThrow")
		elseif held.Type == "Pistol" then
			throwRock(player, held.Part, direction, CombatConfig.Items.Weapon, "PistolThrow")
		else
			throwRock(player, held.Part, direction, CombatConfig.Items.Rock, "RockThrow")
		end
	elseif action == "EquipSlot" then
		setEquippedSlot(player, tonumber(direction))
	end
end)

ShopPurchaseEvent.OnServerEvent:Connect(function(player, itemKey)
	if gameState ~= "Playing" then
		ShopResultEvent:FireClient(player, false, "Shop is only available during a match.")
		return
	end
	if not activeTeam[player.UserId] then
		ShopResultEvent:FireClient(player, false, "You are not on the active team.")
		return
	end
	if not player.Character then
		ShopResultEvent:FireClient(player, false, "Character not ready.")
		return
	end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		ShopResultEvent:FireClient(player, false, "You cannot shop while downed.")
		return
	end

	local shopConfig = CombatConfig.Shop or {}
	local cost = shopConfig[itemKey]
	if not cost then
		ShopResultEvent:FireClient(player, false, "Unknown item.")
		return
	end

	if not trySpendMoney(player, cost, "Shop") then
		ShopResultEvent:FireClient(player, false, "Not enough money.")
		return
	end

	if itemKey == "HealthPack" then
		local healAmount = CombatConfig.Items.Health.HealAmount
		local before = humanoid.Health
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
		if humanoid.Health <= before then
			awardMoney(player, cost, "Refund")
			ShopResultEvent:FireClient(player, false, "Health is already full.")
			return
		end
		ShopResultEvent:FireClient(player, true, "Purchased Health Pack.")
		return
	end

	if itemKey == "Shield" then
		local shieldConfig = CombatConfig.Items.Shield or {}
		local maxAbsorb = shieldConfig.MaxAbsorb or 75
		local absorbAmount = shieldConfig.AbsorbAmount or 35
		playerShield[player.UserId] = math.min(maxAbsorb, (playerShield[player.UserId] or 0) + absorbAmount)
		ShopResultEvent:FireClient(player, true, "Purchased Shield.")
		return
	end

	if itemKey == "StaminaPotion" then
		StaminaBoostEvent:FireClient(player, CombatConfig.Items.StaminaPotion and CombatConfig.Items.StaminaPotion.RestoreAmount or 45)
		ShopResultEvent:FireClient(player, true, "Purchased Stamina Potion.")
		return
	end

	if itemKey == "Weapon" or itemKey == "Rock" or itemKey == "Sword" or itemKey == "Pistol" then
		if addInventoryItem(player, itemKey) then
			ShopResultEvent:FireClient(player, true, "Purchased " .. itemKey .. ".")
		else
			awardMoney(player, cost, "Refund")
			ShopResultEvent:FireClient(player, false, "Inventory full.")
		end
		return
	end

	awardMoney(player, cost, "Refund")
	ShopResultEvent:FireClient(player, false, "Purchase failed.")
end)

------------------------------------------------------------
-- PLAYER DEATH TRACKING
------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	setMoney(player, playerMoney[player.UserId] or 0)
	playerShield[player.UserId] = 0
	playerInventories[player.UserId] = {
		slots = {nil, nil, nil},
		equippedSlot = 1,
	}
	refreshLobbyTeamStatus()
	player.CharacterAdded:Connect(function(character)
		clearHeldItem(player)
		playerShield[player.UserId] = 0
		playerInventories[player.UserId] = {
			slots = {nil, nil, nil},
			equippedSlot = 1,
		}
		sendInventoryState(player)

		local blockVal = Instance.new("BoolValue")
		blockVal.Name = "IsBlocking"
		blockVal.Value = false
		blockVal.Parent = character

		local dodgeVal = Instance.new("BoolValue")
		dodgeVal.Name = "IsDodging"
		dodgeVal.Value = false
		dodgeVal.Parent = character

		local humanoid = character:WaitForChild("Humanoid")
		if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			warn(("[GameManager] Player '%s' spawned as %s, expected R15"):format(
				player.Name,
				tostring(humanoid.RigType)
			))
		end
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
	playerInventories[player.UserId] = nil
	playerShield[player.UserId] = nil
	itemUseCooldowns[player.UserId] = nil
	grabUseCooldowns[player.UserId] = nil
	playerMoney[player.UserId] = nil
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
