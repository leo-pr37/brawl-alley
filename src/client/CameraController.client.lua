--[[
	CameraController (Client)
	Beat-em-up style camera: follows player from an elevated angle,
	slightly behind and above, giving a classic arcade perspective.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Camera settings
local CAMERA_OFFSET = Vector3.new(0, 25, 30) -- elevated behind
local CAMERA_LOOK_OFFSET = Vector3.new(0, -2, 0) -- look slightly below center
local CAMERA_SMOOTHING = 0.1
local CAMERA_MODE = "Fixed" -- Fixed angle, classic beat-em-up

local currentCameraPos = nil
local initialized = false

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

	-- Smooth follow
	currentCameraPos = currentCameraPos:Lerp(targetPos, CAMERA_SMOOTHING)
	camera.CFrame = CFrame.new(currentCameraPos, lookAt)
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

print("[BrawlAlley] CameraController loaded")
