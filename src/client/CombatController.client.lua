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
local StateMachine = require(Shared:WaitForChild("StateMachine"))
local CharacterStates = require(Shared:WaitForChild("CharacterStates"))

-- Remote events
local AttackEvent = ReplicatedStorage:WaitForChild("AttackEvent")
local BlockEvent = ReplicatedStorage:WaitForChild("BlockEvent")
local DodgeEvent = ReplicatedStorage:WaitForChild("DodgeEvent")
local GrabEvent = ReplicatedStorage:WaitForChild("GrabEvent")
local ComicBubbleEvent = ReplicatedStorage:WaitForChild("ComicBubbleEvent", 10)
local ItemInteractEvent = ReplicatedStorage:WaitForChild("ItemInteractEvent")
local HeldItemStateEvent = ReplicatedStorage:WaitForChild("HeldItemStateEvent")
local EnemyHitEvent = ReplicatedStorage:WaitForChild("EnemyHitEvent")

-- Combat state
local comboCount = 0
local lastAttackTime = 0
local lastDodgeTime = 0
local isBlocking = false
local mouseHoldStart = 0
local isHolding = false
local attackCooldownEnd = 0
local lastGrabTime = 0
local heldItemType = nil
local lastItemUseTime = 0
local isSprinting = false
local playerSM = nil -- StateMachine, created on CharacterAdded

local BASE_WALK_SPEED = CombatConfig.PlayerWalkSpeed or 20
local SPRINT_WALK_SPEED = BASE_WALK_SPEED * 1.5
local grabConfig = CombatConfig.Grab or {}
local audioConfig = CombatConfig.Audio or {}
local sfxConfig = audioConfig.SFX or {}

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

local function setSprint(enabled)
	isSprinting = enabled and true or false
	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid.WalkSpeed = isSprinting and SPRINT_WALK_SPEED or BASE_WALK_SPEED
end

local function getLookDirection()
	local hrp = getHumanoidRootPart()
	if hrp then
		return hrp.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
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
	local char = getCharacter()
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Quick upward impulse for visual jump
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(0, math.huge, 0)
	bv.Velocity = Vector3.new(0, 30, 0)
	bv.Parent = hrp
	game:GetService("Debris"):AddItem(bv, 0.15)
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

	ItemInteractEvent:FireServer("Use", getLookDirection())

	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) then
		if heldItemType == "Weapon" then
			AnimationManager.PlayHeavyPunch(char)
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

	ItemInteractEvent:FireServer("Throw", getLookDirection())

	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) then
		AnimationManager.PlayHeavyPunch(char)
	end
	return true
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
		AnimationManager.PlayDodge(char2)
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
		BlockEvent:FireServer(true)
		if playerSM then playerSM:SetState("Blocking", true) end
		playSfx(sfxBlock)
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.PlayBlock(char)
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		doDodge()
	end

	if input.KeyCode == Enum.KeyCode.Q then
		doDodge()
	end

	if input.KeyCode == Enum.KeyCode.E then
		tryPickupItem()
	end

	if input.KeyCode == Enum.KeyCode.G then
		tryGrabSuplex()
	end

	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		setSprint(true)
	end

	if input.KeyCode == Enum.KeyCode.R then
		tryDropHeldItem()
	end

	if input.KeyCode == Enum.KeyCode.F then
		tryThrowHeldItem()
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
		if playerSM and playerSM:GetState() == "Blocking" then
			playerSM:SetState("Idle", true)
		end
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.PlayUnblock(char)
		end
	end

	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		setSprint(false)
	end
end)

-- Blocking visual + combo reset + charge indicator
RunService.RenderStepped:Connect(function()
	local char = getCharacter()
	if not char then return end

	local blockShield = char:FindFirstChild("BlockShield")
	if isBlocking and isAlive() then
		if not blockShield then
			blockShield = Instance.new("Part")
			blockShield.Name = "BlockShield"
			blockShield.Shape = Enum.PartType.Ball
			blockShield.Size = Vector3.new(5, 5, 5)
			blockShield.Transparency = 0.7
			blockShield.BrickColor = BrickColor.new("Cyan")
			blockShield.Material = Enum.Material.ForceField
			blockShield.CanCollide = false
			blockShield.Anchored = false
			blockShield.Parent = char

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = char:FindFirstChild("HumanoidRootPart")
			weld.Part1 = blockShield
			weld.Parent = blockShield
		end
	else
		if blockShield then
			blockShield:Destroy()
		end
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
local DamageEvent = ReplicatedStorage:WaitForChild("DamageEvent")
DamageEvent.OnClientEvent:Connect(function(damage, wasBlocked, sourcePos)
	if wasBlocked then return end
	playSfx(sfxHurt)
	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) and not isBlocking then
		if playerSM then playerSM:SetState("HitStun", true) end
		AnimationManager.PlayHitReaction(char)
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

HeldItemStateEvent.OnClientEvent:Connect(function(itemType)
	local wasHolding = heldItemType ~= nil
	heldItemType = itemType
	if itemType and not wasHolding and sfxPickup then
		playSfx(sfxPickup)
	elseif not itemType then
		lastItemUseTime = 0
	end
end)

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED
	end
	isSprinting = false

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

	local state = playerSM:GetState()
	-- Only auto-set locomotion states when not in a locked/action state
	if not playerSM:IsLocked() then
		local moving = humanoid.MoveDirection.Magnitude > 0.05
		if moving then
			local want = isSprinting and "Sprinting" or "Walking"
			if state ~= want then playerSM:SetState(want) end
		else
			if state ~= "Idle" and state ~= "Blocking" then
				playerSM:SetState("Idle")
			end
		end
	end

	playerSM:Update(dt)
end)

print("[BrawlAlley] CombatController loaded")
