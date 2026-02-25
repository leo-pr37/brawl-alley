--[[
	CombatController (Client)
	Handles player input for combat: attacks, blocking, dodging.
	Manages combo state and communicates with server.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))

-- Remote events
local AttackEvent = ReplicatedStorage:WaitForChild("AttackEvent")
local BlockEvent = ReplicatedStorage:WaitForChild("BlockEvent")
local DodgeEvent = ReplicatedStorage:WaitForChild("DodgeEvent")

-- Combat state
local comboCount = 0
local lastAttackTime = 0
local lastDodgeTime = 0
local isBlocking = false
local mouseHoldStart = 0
local isHolding = false
local attackCooldownEnd = 0

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

-- Get the direction the player is looking
local function getLookDirection()
	local hrp = getHumanoidRootPart()
	if hrp then
		return hrp.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

-- Attack visual feedback using AnimationManager
local function playAttackAnimation(attackType)
	local char = getCharacter()
	if not char then return end

	-- Set up joints on player character if not done yet
	if not AnimationManager.HasJoints(char) then
		AnimationManager.SetupJoints(char, 1)
	end

	if attackType == "HeavyAttack" then
		AnimationManager.PlayHeavyPunch(char)
	else
		-- Light attack uses combo index for varied animations
		AnimationManager.PlayLightPunch(char, comboCount)
	end
end

-- Perform attack
local function doAttack(attackType)
	if not isAlive() then return end
	if isBlocking then return end

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

-- Dodge
local function doDodge()
	if not isAlive() then return end
	local now = tick()
	if now - lastDodgeTime < CombatConfig.DodgeCooldown then return end
	lastDodgeTime = now

	-- Stop blocking if dodging
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

	-- Play dodge animation
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

	-- Left click: start attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHoldStart = tick()
		isHolding = true
	end

	-- Right click: block
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isBlocking = true
		BlockEvent:FireServer(true)
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.PlayBlock(char)
		end
	end

	-- Shift: dodge
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		doDodge()
	end

	-- Q: dodge alternative
	if input.KeyCode == Enum.KeyCode.Q then
		doDodge()
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	-- Left click released: determine attack type
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
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

	-- Right click released: stop blocking
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isBlocking = false
		BlockEvent:FireServer(false)
		local char = getCharacter()
		if char and AnimationManager.HasJoints(char) then
			AnimationManager.PlayUnblock(char)
		end
	end
end)

-- Blocking visual
RunService.RenderStepped:Connect(function()
	local char = getCharacter()
	if not char then return end

	-- Block visual indicator
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
			-- Show charge ready visual
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
	if wasBlocked then return end -- no flinch when blocking
	local char = getCharacter()
	if char and AnimationManager.HasJoints(char) and not isBlocking then
		AnimationManager.PlayHitReaction(char)
	end
end)

-- Setup joints on character spawn
player.CharacterAdded:Connect(function(character)
	task.wait(0.5) -- wait for character to fully load
	if not AnimationManager.HasJoints(character) then
		AnimationManager.SetupJoints(character, 1)
	end
end)

-- Setup joints on current character if it exists
if player.Character then
	task.spawn(function()
		task.wait(0.5)
		if player.Character and not AnimationManager.HasJoints(player.Character) then
			AnimationManager.SetupJoints(player.Character, 1)
		end
	end)
end

print("[BrawlAlley] CombatController loaded")
