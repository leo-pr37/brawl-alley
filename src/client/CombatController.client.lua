--[[
	CombatController (Client)
	Handles player input for combat: attacks, blocking, dodging.
	Manages combo state and communicates with server.
	Includes exaggerated attack animations (uppercut jump, heavy lunge).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))
local ComicBubbles = require(Shared:WaitForChild("ComicBubbles"))
local StateMachine = require(Shared:WaitForChild("RuntimeStateMachine"))
local CharacterStates = require(Shared:WaitForChild("CharacterStates"))

-- Remote events
local Remotes = Shared:WaitForChild("Remotes", 10)
if not Remotes then
	error("[CombatController] Shared.Remotes not found")
end

local function getRemote(name)
	local remote = Remotes:FindFirstChild(name) or Remotes:WaitForChild(name, 10)
	if not remote then
		remote = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 2)
	end
	if not remote then
		error(("[CombatController] Remote not found: %s"):format(name))
	end
	return remote
end

local AttackEvent = getRemote("AttackEvent")
local BlockEvent = getRemote("BlockEvent")
local DodgeEvent = getRemote("DodgeEvent")
local GrabEvent = getRemote("GrabEvent")
local ComicBubbleEvent = getRemote("ComicBubbleEvent")
local ItemInteractEvent = getRemote("ItemInteractEvent")
local HeldItemStateEvent = getRemote("HeldItemStateEvent")
local EnemyHitEvent = getRemote("EnemyHitEvent")
local StaminaBoostEvent = getRemote("StaminaBoost")

-- Combat state
local comboCount = 0
local lastAttackTime = 0
local lastDodgeTime = 0
local lastUppercutJumpTime = 0
local isBlocking = false
local mouseHoldStart = 0
local isHolding = false
local attackCooldownEnd = 0
local lastGrabTime = 0
local heldItemType = nil
local inventorySlots = {nil, nil, nil}
local equippedSlot = 1
local lastItemUseTime = 0
local isSprinting = false
local playerSM = nil -- StateMachine, created on CharacterAdded
local blockPoseActive = false
local pistolPoseActive = false

local BASE_WALK_SPEED = CombatConfig.PlayerWalkSpeed or 20
local SPRINT_WALK_SPEED = BASE_WALK_SPEED * 1.5
local UPPERCUT_JUMP_COOLDOWN = 0.35
local grabConfig = CombatConfig.Grab or {}
local staminaConfig = CombatConfig.Stamina or {}
local maxStamina = staminaConfig.Max or 100
local stamina = maxStamina
local lastStaminaUseTime = 0
local savedJumpPower = nil
local savedJumpHeight = nil
local blockJumpSuppressed = false
local audioConfig = CombatConfig.Audio or {}
local sfxConfig = audioConfig.SFX or {}
local staminaEvent = ReplicatedStorage:FindFirstChild("StaminaUpdate")
if not staminaEvent then
	staminaEvent = Instance.new("BindableEvent")
	staminaEvent.Name = "StaminaUpdate"
	staminaEvent.Parent = ReplicatedStorage
end
local inventoryEvent = ReplicatedStorage:FindFirstChild("InventoryUpdate")
if not inventoryEvent then
	inventoryEvent = Instance.new("BindableEvent")
	inventoryEvent.Name = "InventoryUpdate"
	inventoryEvent.Parent = ReplicatedStorage
end

local function createSfx(name, soundId, volume)
	if not soundId or soundId == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = soundId
	s.Volume = volume or 0.45
	s.Parent = SoundService
	return s
end

local sfxAttackLight = createSfx("AttackLight", sfxConfig.AttackLightId, sfxConfig.Volume)
local sfxAttackHeavy = createSfx("AttackHeavy", sfxConfig.AttackHeavyId, sfxConfig.Volume)
local sfxHit = createSfx("Hit", sfxConfig.HitId, sfxConfig.Volume)
local sfxHurt = createSfx("Hurt", sfxConfig.HurtId, sfxConfig.Volume)
local sfxBlock = createSfx("Block", sfxConfig.BlockId, sfxConfig.Volume)
local sfxPickup = createSfx("Pickup", sfxConfig.PickupId, sfxConfig.Volume)

local sfxToPreload = {}
for _, sfx in ipairs({sfxAttackLight, sfxAttackHeavy, sfxHit, sfxHurt, sfxBlock, sfxPickup}) do
	if sfx then
		table.insert(sfxToPreload, sfx)
	end
end
if #sfxToPreload > 0 then
	task.spawn(function()
		ContentProvider:PreloadAsync(sfxToPreload)
	end)
end

local function playSfx(sound)
	if not sound then return end
	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

-- Get character safely
local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoidRootPart()
	local char = getCharacter()
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local char = getCharacter()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive()
	local h = getHumanoid()
	return h and h.Health > 0
end

local function disableDefaultAnimate(character)
	-- Keep Roblox default Animate enabled for normal locomotion.
	if not character then return end
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Disabled = false
	end
end

local function setBlockJumpSuppressed(enabled)
	local humanoid = getHumanoid()
	if not humanoid then return end

	if enabled then
		if blockJumpSuppressed then return end
		blockJumpSuppressed = true
		savedJumpPower = humanoid.JumpPower
		savedJumpHeight = humanoid.JumpHeight
		humanoid.Jump = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		if humanoid.UseJumpPower then
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = 0
		end
	else
		if not blockJumpSuppressed then return end
		blockJumpSuppressed = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		if humanoid.UseJumpPower then
			humanoid.JumpPower = savedJumpPower or CombatConfig.PlayerJumpPower or 50
		else
			humanoid.JumpHeight = savedJumpHeight or 7.2
		end
	end
end

local function setSprint(enabled)
	if enabled then
		local minToStartSprint = staminaConfig.MinToStartSprint or 12
		if stamina < minToStartSprint then
			enabled = false
		end
	end
	isSprinting = enabled and true or false
	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid.WalkSpeed = isSprinting and SPRINT_WALK_SPEED or BASE_WALK_SPEED
end

local function pushStaminaUpdate()
	if staminaEvent then
		staminaEvent:Fire(stamina, maxStamina)
	end
end

local function pushInventoryUpdate()
	if inventoryEvent then
		inventoryEvent:Fire({
			slots = {inventorySlots[1], inventorySlots[2], inventorySlots[3]},
			equippedSlot = equippedSlot,
			equipped = heldItemType,
		})
	end
end

local function consumeStamina(amount)
	if amount <= 0 then
		return true
	end
	if stamina < amount then
		return false
	end
	stamina = math.max(0, stamina - amount)
	lastStaminaUseTime = tick()
	if stamina <= 0 and isSprinting then
		setSprint(false)
	end
	pushStaminaUpdate()
	return true
end

local function getLookDirection()
	local hrp = getHumanoidRootPart()
	if hrp then
		return hrp.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

local function getCameraAimDirection()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.LookVector
	end
	return getLookDirection()
end

local function getAutoAimDirection()
	local hrp = getHumanoidRootPart()
	if not hrp then
		return getLookDirection()
	end

	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return getLookDirection()
	end

	local bestDir = nil
	local bestDist = math.huge
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				local delta = (enemy.PrimaryPart.Position + Vector3.new(0, 1.5, 0)) - hrp.Position
				local dist = delta.Magnitude
				if dist > 0.001 and dist < bestDist then
					bestDist = dist
					bestDir = delta.Unit
				end
			end
		end
	end

	return bestDir or getLookDirection()
end

local function findLocalGrabTarget()
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	local hrp = getHumanoidRootPart()
	if not enemiesFolder or not hrp then return nil end

	local maxRange = grabConfig.Range or 7
	local facing = hrp.CFrame.LookVector
	local bestEnemy = nil
	local bestDist = maxRange + 0.001

	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				local delta = enemy.PrimaryPart.Position - hrp.Position
				local dist = delta.Magnitude
				if dist <= maxRange and dist < bestDist then
					local dot = dist > 0 and delta.Unit:Dot(facing) or 1
					if dot > 0.2 then
						bestEnemy = enemy
						bestDist = dist
					end
				end
			end
		end
	end

	return bestEnemy
end

-- Exaggerated uppercut: player jumps up
local function doUppercutJump()
	local now = tick()
	if now - lastUppercutJumpTime < UPPERCUT_JUMP_COOLDOWN then
		return
	end
	lastUppercutJumpTime = now

	local char = getCharacter()
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not humanoid then return end

	-- One-shot upward boost is smoother than BodyVelocity and avoids physics jitter.
	local vel = hrp.AssemblyLinearVelocity
	local boostedY = math.min(math.max(vel.Y, 0) + 18, 26)
	hrp.AssemblyLinearVelocity = Vector3.new(vel.X, boostedY, vel.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

-- Exaggerated heavy punch: forward lunge
local function doHeavyLunge()
	local char = getCharacter()
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local dir = hrp.CFrame.LookVector
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
	bv.Velocity = dir * 25
	bv.Parent = hrp
	game:GetService("Debris"):AddItem(bv, 0.15)
end

-- Attack visual feedback using AnimationManager
local function playAttackAnimation(attackType)
	local char = getCharacter()
	if not char then return end

	if not AnimationManager.HasJoints(char) then
		AnimationManager.SetupJoints(char, 1)
	end

	if attackType == "HeavyAttack" then
		AnimationManager.PlayHeavyPunch(char)
		doHeavyLunge()
	else
		-- Light attack uses combo index for varied animations
		AnimationManager.PlayLightPunch(char, comboCount)
		-- Uppercut on combo 4
		if comboCount == 4 then
			doUppercutJump()
		end
	end
end

-- Perform attack
local function doAttack(attackType)
	if not isAlive() then return end
	if isBlocking then return end
	if heldItemType then return end
	if playerSM and playerSM:IsLocked() then return end

	local now = tick()
	if now < attackCooldownEnd then return end

	-- Set state machine to Attacking
	if playerSM then playerSM:SetState("Attacking", true) end

	local config = CombatConfig.Attacks[attackType]
	if not config then return end
	local attackStaminaCost = attackType == "HeavyAttack"
		and (staminaConfig.HeavyAttackCost or 18)
		or (staminaConfig.LightAttackCost or 8)
	if not consumeStamina(attackStaminaCost) then
		return
	end

	-- Combo logic
	if attackType == "LightAttack" then
		if now - lastAttackTime <= config.ComboWindow then
			comboCount = math.min(comboCount + 1, CombatConfig.MaxComboHits)
		else
			comboCount = 1
		end
	else
		comboCount = 0
	end

	lastAttackTime = now
	attackCooldownEnd = now + config.Cooldown

	local hrp = getHumanoidRootPart()
	local dir = getLookDirection()
	local pos = hrp and hrp.Position or Vector3.new(0, 0, 0)

	-- Send to server
	AttackEvent:FireServer(attackType, pos, dir)

	-- Play local effects
	playAttackAnimation(attackType)
	if attackType == "HeavyAttack" then
		playSfx(sfxAttackHeavy)
	else
		playSfx(sfxAttackLight)
	end

	-- Fire combo update for UI
	local comboEvent = ReplicatedStorage:FindFirstChild("ComboUpdate")
	if not comboEvent then
		comboEvent = Instance.new("BindableEvent")
		comboEvent.Name = "ComboUpdate"
		comboEvent.Parent = ReplicatedStorage
	end
	comboEvent:Fire(comboCount, attackType)
end

local function tryUseHeldItem()
	if not heldItemType or not isAlive() or isBlocking then
		return false
	end

	local now = tick()
	if now - lastItemUseTime < CombatConfig.Items.ItemUseInputCooldown then
		return true
	end
	lastItemUseTime = now

	local useDirection
	if heldItemType == "Pistol" then
		useDirection = getCameraAimDirection()
	elseif heldItemType == "Rock" then
		useDirection = getAutoAimDirection()
	else
		useDirection = getLookDirection()
	end
	ItemInteractEvent:FireServer("Use", useDirection)

	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) then
		if heldItemType == "Weapon" or heldItemType == "Sword" then
			AnimationManager.PlayHeavyPunch(char)
		elseif heldItemType == "Pistol" then
			AnimationManager.PlayLightPunch(char, 2)
		else
			AnimationManager.PlayLightPunch(char, 1)
		end
	end
	return true
end

local function tryPickupItem()
	if not isAlive() then return end
	ItemInteractEvent:FireServer("Pickup")
end

local function tryDropHeldItem()
	if not heldItemType or not isAlive() then return end
	ItemInteractEvent:FireServer("Drop", getLookDirection())
end

local function tryThrowHeldItem()
	if not heldItemType or not isAlive() or isBlocking then
		return false
	end

	local now = tick()
	if now - lastItemUseTime < CombatConfig.Items.ItemUseInputCooldown then
		return true
	end
	lastItemUseTime = now

	ItemInteractEvent:FireServer("Throw", getAutoAimDirection())

	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) then
		AnimationManager.PlayHeavyPunch(char)
	end
	return true
end

local function equipInventorySlot(slotIndex)
	if slotIndex < 1 or slotIndex > 3 then
		return
	end
	ItemInteractEvent:FireServer("EquipSlot", slotIndex)
end

-- Dodge
local function doDodge()
	if not isAlive() then return end
	if playerSM and playerSM:IsLocked() then return end
	local now = tick()
	if now - lastDodgeTime < CombatConfig.DodgeCooldown then return end
	lastDodgeTime = now

	if isBlocking then
		isBlocking = false
		BlockEvent:FireServer(false)
		setBlockJumpSuppressed(false)
	end

	if playerSM then playerSM:SetState("Dodging", true) end

	local moveDir = Vector3.new(0, 0, 0)
	local hrp = getHumanoidRootPart()
	if hrp then
		local humanoid = getHumanoid()
		if humanoid and humanoid.MoveDirection.Magnitude > 0 then
			moveDir = humanoid.MoveDirection.Unit
		else
			moveDir = hrp.CFrame.LookVector
		end
	end

	DodgeEvent:FireServer(moveDir)

	local char2 = getCharacter()
	if char2 and AnimationManager.HasJoints(char2) then
		AnimationManager.PlayDodge(char2, moveDir)
	end

	-- Visual: brief transparency
	task.spawn(function()
		local char = getCharacter()
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0.6
			end
		end
		task.wait(CombatConfig.DodgeIFrames)
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			end
		end
	end)
end

local function tryGrabSuplex()
	if not isAlive() then return false end
	if isBlocking or heldItemType then return false end
	if playerSM and playerSM:IsLocked() then return false end

	local now = tick()
	local cooldown = grabConfig.Cooldown or 1.25
	if now - lastGrabTime < cooldown then
		return false
	end

	local target = findLocalGrabTarget()
	if not target then
		return false
	end

	lastGrabTime = now
	isHolding = false

	if playerSM then
		playerSM:SetState("Grabbing", true)
	else
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.PlaySuplex(char)
		end
	end

	GrabEvent:FireServer(target)
	playSfx(sfxAttackHeavy)
	return true
end

------------------------------------------------------------
-- INPUT HANDLING
------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not tryUseHeldItem() then
			mouseHoldStart = tick()
			isHolding = true
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if playerSM and playerSM:IsLocked() then return end
		isBlocking = true
		blockPoseActive = true
		BlockEvent:FireServer(true)
		setBlockJumpSuppressed(true)
		playSfx(sfxBlock)
	end

	if input.KeyCode == Enum.KeyCode.Q then
		doDodge()
	end

	if input.KeyCode == Enum.KeyCode.Space and isBlocking then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.Jump = false
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		tryPickupItem()
	end

	if input.KeyCode == Enum.KeyCode.G then
		tryGrabSuplex()
	end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end

	if input.KeyCode == Enum.KeyCode.R then
		tryDropHeldItem()
	end

	if input.KeyCode == Enum.KeyCode.F then
		tryThrowHeldItem()
	end

	if input.KeyCode == Enum.KeyCode.One then
		equipInventorySlot(1)
	end
	if input.KeyCode == Enum.KeyCode.Two then
		equipInventorySlot(2)
	end
	if input.KeyCode == Enum.KeyCode.Three then
		equipInventorySlot(3)
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if heldItemType then return end
		if isHolding then
			isHolding = false
			local holdDuration = tick() - mouseHoldStart
			if holdDuration >= CombatConfig.Attacks.HeavyAttack.ChargeTime then
				doAttack("HeavyAttack")
			else
				doAttack("LightAttack")
			end
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not isBlocking then return end
		isBlocking = false
		BlockEvent:FireServer(false)
		setBlockJumpSuppressed(false)
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.ClearBlockPose(char)
		end
		blockPoseActive = false
	end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

-- Blocking visual + combo reset + charge indicator
RunService.RenderStepped:Connect(function()
	local char = getCharacter()
	if not char then return end

	local blockShield = char:FindFirstChild("BlockShield")
	if isBlocking and isAlive() then
		if pistolPoseActive then
			AnimationManager.ClearPistolPose(char)
			pistolPoseActive = false
		end
		AnimationManager.HoldBlockPose(char)
		blockPoseActive = true
		if not blockShield then
			blockShield = Instance.new("Highlight")
			blockShield.Name = "BlockShield"
			blockShield.FillColor = Color3.fromRGB(80, 220, 255)
			blockShield.FillTransparency = 0.7
			blockShield.OutlineColor = Color3.fromRGB(20, 120, 160)
			blockShield.OutlineTransparency = 0.15
			blockShield.DepthMode = Enum.HighlightDepthMode.Occluded
			blockShield.Parent = char
		end
	else
		if blockPoseActive then
			AnimationManager.ClearBlockPose(char)
			blockPoseActive = false
		end
		if blockShield then
			blockShield:Destroy()
		end
	end

	if heldItemType == "Pistol" and isAlive() and not isBlocking then
		AnimationManager.HoldPistolPose(char, getCameraAimDirection())
		pistolPoseActive = true
	elseif pistolPoseActive then
		AnimationManager.ClearPistolPose(char)
		pistolPoseActive = false
	end

	-- Combo reset
	if comboCount > 0 and (tick() - lastAttackTime) > CombatConfig.ComboResetTime then
		comboCount = 0
		local comboEvent = ReplicatedStorage:FindFirstChild("ComboUpdate")
		if comboEvent then
			comboEvent:Fire(0, "reset")
		end
	end

	-- Heavy attack charge indicator
	if isHolding and isAlive() then
		local holdDuration = tick() - mouseHoldStart
		local chargeThreshold = CombatConfig.Attacks.HeavyAttack.ChargeTime
		if holdDuration >= chargeThreshold then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local glow = hrp:FindFirstChild("ChargeGlow")
				if not glow then
					glow = Instance.new("PointLight")
					glow.Name = "ChargeGlow"
					glow.Color = Color3.fromRGB(255, 150, 0)
					glow.Brightness = 3
					glow.Range = 10
					glow.Parent = hrp
				end
			end
		end
	else
		local char2 = getCharacter()
		if char2 then
			local hrp = char2:FindFirstChild("HumanoidRootPart")
			if hrp then
				local glow = hrp:FindFirstChild("ChargeGlow")
				if glow then glow:Destroy() end
			end
		end
	end
end)

-- Hit reaction when taking damage
local DamageEvent = getRemote("DamageEvent")
DamageEvent.OnClientEvent:Connect(function(damage, wasBlocked, sourcePos)
	if wasBlocked then return end
	playSfx(sfxHurt)
	local char = getCharacter()
	if char and not isBlocking then
		if playerSM then
			playerSM:SetState("HitStun", true)
		elseif AnimationManager.HasJoints(char) then
			AnimationManager.PlayHitReaction(char)
		end
	end
end)

EnemyHitEvent.OnClientEvent:Connect(function(enemy, hitType)
	if hitType ~= "hit" or not sfxHit or not enemy or not enemy:IsA("Model") or not enemy.PrimaryPart then
		return
	end
	local hrp = getHumanoidRootPart()
	if not hrp then return end
	if (enemy.PrimaryPart.Position - hrp.Position).Magnitude <= 45 then
		playSfx(sfxHit)
	end
end)

-- Listen for comic bubble events from server
if ComicBubbleEvent then
	ComicBubbleEvent.OnClientEvent:Connect(function(enemy, hitType, worldPos)
		if enemy and enemy:IsA("Model") and enemy.PrimaryPart then
			ComicBubbles.Spawn(enemy.PrimaryPart, hitType, worldPos)
		elseif worldPos then
			ComicBubbles.Spawn(nil, hitType, worldPos)
		end
	end)
end

HeldItemStateEvent.OnClientEvent:Connect(function(payload)
	local itemType = payload
	if typeof(payload) == "table" then
		itemType = payload.equipped
		local slots = payload.slots or {}
		inventorySlots = {slots[1], slots[2], slots[3]}
		equippedSlot = payload.equippedSlot or 1
	end

	local wasHolding = heldItemType ~= nil
	heldItemType = itemType
	pushInventoryUpdate()
	if itemType and not wasHolding and sfxPickup then
		playSfx(sfxPickup)
	elseif not itemType then
		lastItemUseTime = 0
	end
end)

StaminaBoostEvent.OnClientEvent:Connect(function(amount)
	stamina = math.min(maxStamina, stamina + (amount or 0))
	lastStaminaUseTime = 0
	pushStaminaUpdate()
end)

player.CharacterAdded:Connect(function(character)
	disableDefaultAnimate(character)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED
	end
	isSprinting = false
	isBlocking = false
	blockPoseActive = false
	pistolPoseActive = false
	blockJumpSuppressed = false
	savedJumpPower = nil
	savedJumpHeight = nil
	stamina = maxStamina
	inventorySlots = {nil, nil, nil}
	equippedSlot = 1
	lastStaminaUseTime = 0
	pushStaminaUpdate()
	pushInventoryUpdate()

	local staleBlockShield = character:FindFirstChild("BlockShield")
	if staleBlockShield then
		staleBlockShield:Destroy()
	end
	AnimationManager.ClearBlockPose(character)
	AnimationManager.ClearPistolPose(character)

	-- Create player state machine
	playerSM = StateMachine.new(character, CharacterStates.Player)
	playerSM:SetState("Idle", true)
end)

-- Setup joints on character spawn
player.CharacterAdded:Connect(function(character)
	task.wait(0.5)
	if not AnimationManager.HasJoints(character) then
		AnimationManager.SetupJoints(character, 1)
	end
end)

if player.Character then
	disableDefaultAnimate(player.Character)

	task.spawn(function()
		task.wait(0.5)
		if player.Character and not AnimationManager.HasJoints(player.Character) then
			AnimationManager.SetupJoints(player.Character, 1)
		end
	end)
end

-- Drive player state machine locomotion each frame
RunService.Heartbeat:Connect(function(dt)
	if not playerSM then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if isBlocking then
		humanoid.Jump = false
	end

	local state = playerSM:GetState()
	local staminaBefore = stamina
	local moving = humanoid.MoveDirection.Magnitude > 0.05
	if isSprinting and moving then
		local sprintDrain = staminaConfig.SprintDrainPerSecond or 28
		stamina = math.max(0, stamina - sprintDrain * dt)
		lastStaminaUseTime = tick()
		if stamina <= 0 then
			setSprint(false)
		end
	else
		local regenDelay = staminaConfig.RegenDelay or 0.8
		if tick() - lastStaminaUseTime >= regenDelay then
			local regenPerSecond = staminaConfig.RegenPerSecond or 24
			stamina = math.min(maxStamina, stamina + regenPerSecond * dt)
		end
	end
	if math.abs(stamina - staminaBefore) > 0.01 then
		pushStaminaUpdate()
	end

	-- Only auto-set locomotion states when not in a locked/action state
	if not playerSM:IsLocked() then
		if moving then
			local want = isSprinting and "Sprinting" or "Walking"
			if state ~= want then playerSM:SetState(want) end
		else
			if state ~= "Idle" then
				playerSM:SetState("Idle")
			end
		end
	end

	playerSM:Update(dt)
end)

pushStaminaUpdate()

print("[BrawlAlley] CombatController loaded")
