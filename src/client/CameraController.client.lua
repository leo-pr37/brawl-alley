--[[
	CameraController (Client)
	Third-person over-the-shoulder camera (Fortnite/GTA style).
	Mouse controls camera rotation around player.
	Smooth follow with cinematic lag, offset to right shoulder.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
if _G.MouseFree == nil then
	_G.MouseFree = true
end

-- Camera settings
local CAMERA_DISTANCE = 10        -- distance behind player
local CAMERA_HEIGHT = 4            -- height above player
local CAMERA_SHOULDER_OFFSET = 2   -- offset to the right (over right shoulder)
local CAMERA_SMOOTHING = 0.12      -- lerp factor for position (lower = more lag)
local CAMERA_LOOK_SMOOTHING = 0.15 -- lerp factor for look target
local MOUSE_SENSITIVITY = 0.003    -- mouse sensitivity for rotation

-- State
local yaw = 0          -- horizontal rotation (radians)
local pitch = -0.15     -- vertical rotation (radians), slightly looking down
local PITCH_MIN = -0.61  -- ~-35 degrees (looking up) — prevents camera clipping through floor
local PITCH_MAX = 1.05   -- ~+60 degrees (looking down)
local currentCameraPos = nil
local currentLookAt = nil
local initialized = false
local mouseLocked = false

-- Screen shake state
local shakeIntensity = 0
local shakeDecay = 0
local shakeOffset = Vector3.new(0, 0, 0)

local function getCharacter()
	return player.Character
end

local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	if _G.MouseFree then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		mouseLocked = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		mouseLocked = true
	end
	initialized = true
end

-- Mouse input for camera rotation
UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw = yaw - input.Delta.X * MOUSE_SENSITIVITY
		pitch = math.clamp(pitch - input.Delta.Y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	end
end)

-- Keep mouse locked
UserInputService.WindowFocused:Connect(function()
	if initialized and not _G.MouseFree then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local char = getCharacter()
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not initialized then
		setupCamera()
		-- Initialize yaw based on character facing
		local look = hrp.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end

	-- Ensure camera stays scriptable
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- Only lock mouse when UI doesn't need it
	if not _G.MouseFree then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		mouseLocked = true
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
		mouseLocked = false
	end

	-- Calculate camera position behind and above player
	local playerPos = hrp.Position

	-- Camera orbit based on yaw/pitch
	local cosYaw = math.cos(yaw)
	local sinYaw = math.sin(yaw)
	local cosPitch = math.cos(pitch)
	local sinPitch = math.sin(pitch)

	-- Direction from player to camera (behind them)
	local cameraDir = Vector3.new(
		sinYaw * cosPitch,
		sinPitch,
		cosYaw * cosPitch
	)

	-- Shoulder offset (perpendicular to look direction, on XZ plane)
	local rightDir = Vector3.new(cosYaw, 0, -sinYaw)

	local targetCameraPos = playerPos
		+ cameraDir * CAMERA_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT, 0)
		+ rightDir * CAMERA_SHOULDER_OFFSET

	-- Look target: slightly ahead and above the player
	local lookAheadDir = -cameraDir -- forward is opposite of camera direction
	local targetLookAt = playerPos + Vector3.new(0, 1.5, 0) + Vector3.new(lookAheadDir.X, 0, lookAheadDir.Z).Unit * 3

	-- Initialize positions
	if currentCameraPos == nil then
		currentCameraPos = targetCameraPos
		currentLookAt = targetLookAt
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

	-- Smooth follow with cinematic lag
	currentCameraPos = currentCameraPos:Lerp(targetCameraPos, CAMERA_SMOOTHING)
	currentLookAt = currentLookAt:Lerp(targetLookAt, CAMERA_LOOK_SMOOTHING)

	-- Raycast anti-clip: if camera would be inside geometry, push it forward
	local rayOrigin = playerPos + Vector3.new(0, CAMERA_HEIGHT, 0)
	local rayDir = currentCameraPos - rayOrigin
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayResult = workspace:Raycast(rayOrigin, rayDir, rayParams)
	if rayResult then
		-- Place camera slightly in front of the hit point (0.5 stud buffer)
		local hitDist = (rayResult.Position - rayOrigin).Magnitude
		local fullDist = rayDir.Magnitude
		if hitDist < fullDist then
			local safePos = rayOrigin + rayDir.Unit * math.max(hitDist - 0.5, 1)
			currentCameraPos = safePos
		end
	end

	camera.CFrame = CFrame.new(currentCameraPos + shakeOffset, currentLookAt + shakeOffset)
end)

-- Face character toward camera look direction
RunService.Heartbeat:Connect(function()
	local char = getCharacter()
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then return end

	-- Face character in the direction the camera is looking (XZ only)
	local cosYaw = math.cos(yaw)
	local sinYaw = math.sin(yaw)
	local lookDir = Vector3.new(-sinYaw, 0, -cosYaw)
	if lookDir.Magnitude > 0.1 then
		hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + lookDir)
	end
end)

-- Screen shake from server events
local ScreenShakeEvent = ReplicatedStorage:WaitForChild("ScreenShakeEvent", 5)
if ScreenShakeEvent then
	ScreenShakeEvent.OnClientEvent:Connect(function(intensity, duration)
		shakeIntensity = math.max(shakeIntensity, intensity or 3)
		shakeDecay = duration and (1 / (duration * 60)) or 0.05
	end)
end

local EnemyHitEvent = ReplicatedStorage:WaitForChild("EnemyHitEvent", 5)
if EnemyHitEvent then
	EnemyHitEvent.OnClientEvent:Connect(function(enemy, hitType, sourcePos, attackType)
		if hitType == "hit" then
			local intensity = 1.5
			if attackType == "HeavyAttack" then
				intensity = 3.0
			end
			shakeIntensity = math.max(shakeIntensity, intensity)
			shakeDecay = 0.08
		end
	end)
end

local DamageEvent = ReplicatedStorage:WaitForChild("DamageEvent", 5)
if DamageEvent then
	DamageEvent.OnClientEvent:Connect(function(damage, wasBlocked, sourcePos)
		local intensity = wasBlocked and 1 or math.clamp(damage * 0.3, 1, 6)
		shakeIntensity = math.max(shakeIntensity, intensity)
		shakeDecay = 0.06
	end)
end

print("[BrawlAlley] CameraController loaded (third-person over-shoulder)")
