--[[
	CameraController (Client)
	Beat-em-up style camera: follows player from an elevated angle,
	slightly behind and above, giving a classic arcade perspective.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Camera settings
local CAMERA_OFFSET = Vector3.new(0, 25, 30) -- elevated behind
local CAMERA_LOOK_OFFSET = Vector3.new(0, -2, 0) -- look slightly below center
local CAMERA_SMOOTHING = 0.1
local CAMERA_MODE = "Fixed" -- Fixed angle, classic beat-em-up

local currentCameraPos = nil
local initialized = false

-- Screen shake state
local shakeIntensity = 0
local shakeDecay = 0
local shakeOffset = Vector3.new(0, 0, 0)

local function getCharacter()
	return player.Character
end

local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	initialized = true
end

RunService.RenderStepped:Connect(function(dt)
	local char = getCharacter()
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not initialized then
		setupCamera()
	end

	-- Ensure camera stays scriptable
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local targetPos = hrp.Position + CAMERA_OFFSET
	local lookAt = hrp.Position + CAMERA_LOOK_OFFSET

	if currentCameraPos == nil then
		currentCameraPos = targetPos
	end

	-- Update screen shake
	if shakeIntensity > 0.01 then
		shakeOffset = Vector3.new(
			(math.random() - 0.5) * 2 * shakeIntensity,
			(math.random() - 0.5) * 2 * shakeIntensity,
			(math.random() - 0.5) * 2 * shakeIntensity
		)
		shakeIntensity = shakeIntensity * (1 - shakeDecay)
	else
		shakeOffset = Vector3.new(0, 0, 0)
		shakeIntensity = 0
	end

	-- Smooth follow
	currentCameraPos = currentCameraPos:Lerp(targetPos, CAMERA_SMOOTHING)
	camera.CFrame = CFrame.new(currentCameraPos + shakeOffset, lookAt + shakeOffset)
end)

-- Make the character face toward the mouse position on the ground plane
RunService.Heartbeat:Connect(function()
	local char = getCharacter()
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then return end

	-- Raycast from mouse to find ground point
	local mouse = player:GetMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Intersect with Y=hrp.Position.Y plane
	local planeY = hrp.Position.Y
	if ray.Direction.Y ~= 0 then
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		if t > 0 then
			local groundPoint = ray.Origin + ray.Direction * t
			local lookDir = (groundPoint - hrp.Position)
			lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
			if lookDir.Magnitude > 1 then
				hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + lookDir.Unit)
			end
		end
	end
end)

-- Screen shake from server events (heavy enemy hits)
local ScreenShakeEvent = ReplicatedStorage:WaitForChild("ScreenShakeEvent", 5)
if ScreenShakeEvent then
	ScreenShakeEvent.OnClientEvent:Connect(function(intensity, duration)
		shakeIntensity = math.max(shakeIntensity, intensity or 3)
		shakeDecay = duration and (1 / (duration * 60)) or 0.05
	end)
end

-- Screen shake from local combat (heavy attacks landing)
local EnemyHitEvent = ReplicatedStorage:WaitForChild("EnemyHitEvent", 5)
if EnemyHitEvent then
	EnemyHitEvent.OnClientEvent:Connect(function(enemy, hitType, sourcePos)
		if hitType == "hit" then
			-- Light shake on player hits
			shakeIntensity = math.max(shakeIntensity, 1.5)
			shakeDecay = 0.08
		end
	end)
end

-- Screen shake on taking damage
local DamageEvent = ReplicatedStorage:WaitForChild("DamageEvent", 5)
if DamageEvent then
	DamageEvent.OnClientEvent:Connect(function(damage, wasBlocked, sourcePos)
		local intensity = wasBlocked and 1 or math.clamp(damage * 0.3, 1, 6)
		shakeIntensity = math.max(shakeIntensity, intensity)
		shakeDecay = 0.06
	end)
end

print("[BrawlAlley] CameraController loaded")
