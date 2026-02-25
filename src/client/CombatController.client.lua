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

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))
local ComicBubbles = require(Shared:WaitForChild("ComicBubbles"))

-- Remote events
local AttackEvent = ReplicatedStorage:WaitForChild("AttackEvent")
local BlockEvent = ReplicatedStorage:WaitForChild("BlockEvent")
local DodgeEvent = ReplicatedStorage:WaitForChild("DodgeEvent")
local ComicBubbleEvent = ReplicatedStorage:WaitForChild("ComicBubbleEvent", 10)
local ItemInteractEvent = ReplicatedStorage:WaitForChild("ItemInteractEvent")
local HeldItemStateEvent = ReplicatedStorage:WaitForChild("HeldItemStateEvent")

-- Combat state
local comboCount = 0
local lastAttackTime = 0
local lastDodgeTime = 0
local isBlocking = false
local mouseHoldStart = 0
local isHolding = false
local attackCooldownEnd = 0
local heldItemType = nil
local lastItemUseTime = 0
local isSprinting = false

local BASE_WALK_SPEED = CombatConfig.PlayerWalkSpeed or 20
local SPRINT_WALK_SPEED = BASE_WALK_SPEED * 1.5

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

	local now = tick()
	if now < attackCooldownEnd then return end

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
	local now = tick()
	if now - lastDodgeTime < CombatConfig.DodgeCooldown then return end
	lastDodgeTime = now

	if isBlocking then
		isBlocking = false
		BlockEvent:FireServer(false)
	end

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
		isBlocking = true
		BlockEvent:FireServer(true)
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
		isBlocking = false
		BlockEvent:FireServer(false)
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
	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) and not isBlocking then
		AnimationManager.PlayHitReaction(char)
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
	heldItemType = itemType
	if not itemType then
		lastItemUseTime = 0
	end
end)

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED
	end
	isSprinting = false
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

print("[BrawlAlley] CombatController loaded")
