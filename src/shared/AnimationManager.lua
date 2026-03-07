--[[
	AnimationManager (Shared)
	Procedural animation system using Motor6D C0/C1 CFrame manipulation.
	Works on both client (player) and server (enemies), with R15-first support.
	No Animation assets needed - pure code-driven joint transforms.
	V2: More exaggerated animations, dramatic reactions.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local AnimationManager = {}
AnimationManager.__index = AnimationManager
local resetTokens = setmetatable({}, { __mode = "k" })
local basePoses = setmetatable({}, { __mode = "k" })

-- Joint rest poses (relative to parent)
local REST_POSES = {
	RightShoulder = CFrame.new(1.3, 0.5, 0) * CFrame.Angles(0, 0, 0),
	["Right Shoulder"] = CFrame.new(1.3, 0.5, 0) * CFrame.Angles(0, 0, 0),
	LeftShoulder  = CFrame.new(-1.3, 0.5, 0) * CFrame.Angles(0, 0, 0),
	["Left Shoulder"] = CFrame.new(-1.3, 0.5, 0) * CFrame.Angles(0, 0, 0),
	RightHip      = CFrame.new(0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	["Right Hip"] = CFrame.new(0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	LeftHip       = CFrame.new(-0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	["Left Hip"] = CFrame.new(-0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	Neck          = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, 0),
	RootJoint     = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0),
	Root          = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0),
}

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------
local function getMotor(model, motorName)
	if not model then return nil end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") and desc.Name == motorName then
			return desc
		end
	end
	return nil
end

local function getAllMotors(model)
	local motors = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") then
			motors[desc.Name] = desc
		end
	end
	-- R6 compatibility aliases (default rigs use spaced joint names).
	if not motors.RightShoulder and motors["Right Shoulder"] then
		motors.RightShoulder = motors["Right Shoulder"]
	end
	if not motors.LeftShoulder and motors["Left Shoulder"] then
		motors.LeftShoulder = motors["Left Shoulder"]
	end
	if not motors.RightHip and motors["Right Hip"] then
		motors.RightHip = motors["Right Hip"]
	end
	if not motors.LeftHip and motors["Left Hip"] then
		motors.LeftHip = motors["Left Hip"]
	end
	if not motors.RootJoint and motors.Root then
		motors.RootJoint = motors.Root
	end
	local modelBasePoses = basePoses[model]
	if not modelBasePoses then
		modelBasePoses = {}
		basePoses[model] = modelBasePoses
	end
	for name, motor in pairs(motors) do
		if not modelBasePoses[name] then
			modelBasePoses[name] = motor.C0
		end
	end
	return motors
end

-- Set motor C0 immediately (no tween) — for continuous animations like walking.
-- Applies the same auto-adapt delta as tweenMotor.
local function setMotorDirect(motor, targetC0)
	if not motor then return end
	local model = motor.Parent and motor.Parent.Parent
	if model and basePoses[model] and basePoses[model][motor.Name] then
		local baseC0 = basePoses[model][motor.Name]
		local restKey = motor.Name
		if restKey == "Root" then restKey = "RootJoint" end
		local restC0 = REST_POSES[restKey]
		if restC0 then
			local delta = restC0:Inverse() * targetC0
			targetC0 = baseC0 * delta
		end
	end
	motor.C0 = targetC0
end

local function getBaseC0(motor)
	if not motor then return nil end
	local model = motor.Parent and motor.Parent.Parent
	return model and basePoses[model] and basePoses[model][motor.Name] or motor.C0
end

local function setMotorBaseOffset(motor, offset)
	if not motor then return end
	local baseC0 = getBaseC0(motor)
	if not baseC0 then return end
	motor.C0 = baseC0 * (offset or CFrame.new())
end

local function tweenMotor(motor, targetC0, duration, easingStyle, easingDir)
	if not motor then return nil end
	duration = math.max(duration or 0.1, 0.06)

	-- Auto-adapt: compute rotation delta between animation target and R6 rest
	-- pose, then apply that delta on top of the rig's actual base C0. This lets
	-- R6-authored animations work correctly on R15 rigs whose base C0 may include
	-- different positions or orientations.
	local model = motor.Parent and motor.Parent.Parent
	if model and basePoses[model] and basePoses[model][motor.Name] then
		local baseC0 = basePoses[model][motor.Name]
		local restKey = motor.Name
		if restKey == "Root" then restKey = "RootJoint" end
		local restC0 = REST_POSES[restKey]
		if restC0 then
			local delta = restC0:Inverse() * targetC0
			targetC0 = baseC0 * delta
		end
	end

	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	local tween = TweenService:Create(motor, TweenInfo.new(duration, easingStyle, easingDir), {
		C0 = targetC0
	})
	tween:Play()
	return tween
end

local function cancelQueuedReset(model)
	if not model then return end
	resetTokens[model] = (resetTokens[model] or 0) + 1
end

local function queueReset(model, delayTime, duration)
	if not model then return end
	cancelQueuedReset(model)
	local token = resetTokens[model]
	task.delay(delayTime, function()
		if not model or resetTokens[model] ~= token then return end
		AnimationManager.ResetPose(model, duration)
	end)
end

local function resetSelectedPose(model, duration, motorNames)
	if not model then return end
	duration = duration or 0.2
	local motors = getAllMotors(model)
	local modelBasePoses = basePoses[model]
	for _, name in ipairs(motorNames) do
		local motor = motors[name]
		local rest = motor and ((modelBasePoses and modelBasePoses[motor.Name]) or REST_POSES[motor.Name] or REST_POSES[name])
		if motor and rest then
			tweenMotor(motor, rest, duration)
		end
	end
end

local function queueSelectedReset(model, delayTime, duration, motorNames)
	if not model then return end
	cancelQueuedReset(model)
	local token = resetTokens[model]
	task.delay(delayTime, function()
		if not model or resetTokens[model] ~= token then return end
		resetSelectedPose(model, duration, motorNames)
	end)
end

function AnimationManager.ResetPose(model, duration)
	cancelQueuedReset(model)
	duration = duration or 0.2
	local motors = getAllMotors(model)
	local modelBasePoses = basePoses[model]
	for name, motor in pairs(motors) do
		local rest = (modelBasePoses and modelBasePoses[name]) or REST_POSES[name]
		if rest then
			tweenMotor(motor, rest, duration)
		end
	end
end

function AnimationManager.ResetUpperBodyPose(model, duration)
	resetSelectedPose(model, duration, {"RightShoulder", "LeftShoulder", "Neck"})
end

function AnimationManager.HasJoints(model)
	return getMotor(model, "RightShoulder") ~= nil
		or getMotor(model, "Right Shoulder") ~= nil
end

------------------------------------------------------------
-- JOINT SETUP
------------------------------------------------------------
function AnimationManager.SetupJoints(model, scaleMultiplier)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return
	end
	if AnimationManager.HasJoints(model) then
		return
	end

	local s = scaleMultiplier or 1
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if not torso then return end

	local head = model:FindFirstChild("Head")
	local leftArm = model:FindFirstChild("Left Arm")
	local rightArm = model:FindFirstChild("Right Arm")
	local leftLeg = model:FindFirstChild("Left Leg")
	local rightLeg = model:FindFirstChild("Right Leg")

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("WeldConstraint") then
			desc:Destroy()
		end
	end

	if head then
		local neck = Instance.new("Motor6D")
		neck.Name = "Neck"
		neck.Part0 = torso
		neck.Part1 = head
		neck.C0 = CFrame.new(0, 1.1 * s, 0)
		neck.C1 = CFrame.new(0, 0, 0)
		neck.Parent = torso
	end

	if rightArm then
		local rShoulder = Instance.new("Motor6D")
		rShoulder.Name = "RightShoulder"
		rShoulder.Part0 = torso
		rShoulder.Part1 = rightArm
		rShoulder.C0 = CFrame.new(1.3 * s, 0.5 * s, 0)
		rShoulder.C1 = CFrame.new(0, 0.5 * s, 0)
		rShoulder.Parent = torso
	end

	if leftArm then
		local lShoulder = Instance.new("Motor6D")
		lShoulder.Name = "LeftShoulder"
		lShoulder.Part0 = torso
		lShoulder.Part1 = leftArm
		lShoulder.C0 = CFrame.new(-1.3 * s, 0.5 * s, 0)
		lShoulder.C1 = CFrame.new(0, 0.5 * s, 0)
		lShoulder.Parent = torso
	end

	if rightLeg then
		local rHip = Instance.new("Motor6D")
		rHip.Name = "RightHip"
		rHip.Part0 = torso
		rHip.Part1 = rightLeg
		rHip.C0 = CFrame.new(0.5 * s, -1 * s, 0)
		rHip.C1 = CFrame.new(0, 0.5 * s, 0)
		rHip.Parent = torso
	end

	if leftLeg then
		local lHip = Instance.new("Motor6D")
		lHip.Name = "LeftHip"
		lHip.Part0 = torso
		lHip.Part1 = leftLeg
		lHip.C0 = CFrame.new(-0.5 * s, -1 * s, 0)
		lHip.C1 = CFrame.new(0, 0.5 * s, 0)
		lHip.Parent = torso
	end
end

------------------------------------------------------------
-- PLAYER ANIMATIONS (MORE EXAGGERATED)
------------------------------------------------------------

function AnimationManager.PlayLightPunch(model, comboIndex)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	comboIndex = comboIndex or 1

	if comboIndex == 1 then
		-- Jab: upper-body only so it blends with Roblox locomotion cleanly.
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, -0.1) * CFrame.Angles(math.rad(102), math.rad(-10), math.rad(-8)),
			0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, -0.04) * CFrame.Angles(math.rad(58), math.rad(18), math.rad(10)),
				0.07)
		end
		queueSelectedReset(model, 0.15, 0.12, {"RightShoulder", "LeftShoulder"})

	elseif comboIndex == 2 then
		-- Cross.
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, -0.1) * CFrame.Angles(math.rad(102), math.rad(10), math.rad(8)),
				0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, -0.04) * CFrame.Angles(math.rad(58), math.rad(-18), math.rad(-10)),
			0.07)
		queueSelectedReset(model, 0.15, 0.12, {"RightShoulder", "LeftShoulder"})

	elseif comboIndex == 3 then
		-- Hook.
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, -0.08) * CFrame.Angles(math.rad(88), math.rad(-55), math.rad(20)),
			0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, -0.04) * CFrame.Angles(math.rad(42), math.rad(20), math.rad(16)),
				0.05)
		end
		queueSelectedReset(model, 0.18, 0.15, {"RightShoulder", "LeftShoulder"})

	elseif comboIndex == 4 then
		-- Uppercut wind-up.
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0.02) * CFrame.Angles(math.rad(-24), math.rad(-8), math.rad(-12)),
			0.06)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(25), math.rad(10), math.rad(10)),
				0.06)
		end

		task.delay(0.07, function()
			-- Explode upward.
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, -0.06) * CFrame.Angles(math.rad(155), math.rad(12), math.rad(-12)),
				0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if motors.LeftShoulder then
				tweenMotor(motors.LeftShoulder,
					CFrame.new(-1.3*s, 0.5*s, -0.04) * CFrame.Angles(math.rad(52), math.rad(12), math.rad(-16)),
					0.07)
			end
		end)

		queueSelectedReset(model, 0.3, 0.25, {"RightShoulder", "LeftShoulder"})
	end
end

-- Heavy punch - BIGGER wind-up, more dramatic forward lunge
function AnimationManager.PlayHeavyPunch(model)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	-- Heavy wind-up: upper body only.
	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0.04) * CFrame.Angles(math.rad(10), math.rad(38), math.rad(28)),
		0.18)
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, -0.02) * CFrame.Angles(math.rad(48), math.rad(12), math.rad(18)),
			0.18)
	end

	task.delay(0.2, function()
		-- Slam forward.
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, -0.14) * CFrame.Angles(math.rad(118), math.rad(-28), math.rad(-16)),
			0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, -0.03) * CFrame.Angles(math.rad(30), math.rad(8), math.rad(-12)),
				0.07)
		end
	end)

	queueSelectedReset(model, 0.45, 0.3, {"RightShoulder", "LeftShoulder"})
end

function AnimationManager.PlaySuplex(model)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RootJoint or not motors.RightShoulder then return end

	-- Reach in and clinch.
	tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(12), 0, 0), 0.12)
	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-55), math.rad(-15), math.rad(20)),
		0.12)
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-55), math.rad(15), math.rad(-20)),
			0.12)
	end
	if motors.RightHip then
		tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(20), 0, 0), 0.12)
	end
	if motors.LeftHip then
		tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(20), 0, 0), 0.12)
	end

	task.delay(0.14, function()
		-- Bridge and throw.
		tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-28), 0, 0), 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(130), math.rad(10), math.rad(-10)),
			0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(130), math.rad(-10), math.rad(10)),
				0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-25), 0, 0), 0.14)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-25), 0, 0), 0.14)
		end
	end)

	queueReset(model, 0.58, 0.25)
end

function AnimationManager.PlayBlock(model)
	cancelQueuedReset(model)
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	-- High cover: head tucked, elbows bent, hands near face.
	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3, 0.5, -0.08) * CFrame.Angles(math.rad(88), math.rad(-20), math.rad(62)),
		0.1)
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3, 0.5, -0.08) * CFrame.Angles(math.rad(88), math.rad(20), math.rad(-62)),
			0.1)
	end
	if motors.Neck then
		tweenMotor(motors.Neck,
			CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(10), 0, 0),
			0.1)
	end
end

function AnimationManager.HoldBlockPose(model)
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	-- Persistent high-cover guard while locomotion continues underneath.
	motors.RightShoulder.Transform = CFrame.new()
	setMotorDirect(motors.RightShoulder,
		CFrame.new(1.3, 0.5, -0.1) * CFrame.Angles(math.rad(92), math.rad(-22), math.rad(68)))
	if motors.LeftShoulder then
		motors.LeftShoulder.Transform = CFrame.new()
		setMotorDirect(motors.LeftShoulder,
			CFrame.new(-1.3, 0.5, -0.1) * CFrame.Angles(math.rad(92), math.rad(22), math.rad(-68)))
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.new()
		setMotorDirect(motors.Neck,
			CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(10), 0, 0))
	end
end

function AnimationManager.ClearBlockPose(model)
	local motors = getAllMotors(model)
	if motors.RightShoulder then
		motors.RightShoulder.Transform = CFrame.new()
		setMotorDirect(motors.RightShoulder, REST_POSES.RightShoulder)
	end
	if motors.LeftShoulder then
		motors.LeftShoulder.Transform = CFrame.new()
		setMotorDirect(motors.LeftShoulder, REST_POSES.LeftShoulder)
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.new()
		setMotorDirect(motors.Neck, REST_POSES.Neck)
	end
end

function AnimationManager.PlayUnblock(model)
	AnimationManager.ResetUpperBodyPose(model, 0.15)
end

function AnimationManager.HoldPistolPose(model, aimDirection)
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local localDir = Vector3.new(0, 0, -1)
	if hrp and typeof(aimDirection) == "Vector3" and aimDirection.Magnitude > 0.05 then
		localDir = hrp.CFrame:VectorToObjectSpace(aimDirection.Unit)
	end

	local yaw = math.clamp(math.atan2(localDir.X, -localDir.Z), math.rad(-32), math.rad(32))
	local pitch = math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), math.rad(-28), math.rad(24))

	if motors.RightShoulder then
		motors.RightShoulder.Transform = CFrame.new()
		setMotorBaseOffset(motors.RightShoulder,
			CFrame.new(-0.16, -0.02, -0.18) * CFrame.Angles(math.rad(82) - pitch * 0.9, yaw * 0.8 + math.rad(-10), math.rad(-8)))
	end
	if motors.LeftShoulder then
		motors.LeftShoulder.Transform = CFrame.new()
		setMotorBaseOffset(motors.LeftShoulder,
			CFrame.new(0.22, -0.02, -0.2) * CFrame.Angles(math.rad(60) - pitch * 0.55, yaw * 0.35 + math.rad(38), math.rad(-18)))
	end
	if motors.RightElbow then
		setMotorBaseOffset(motors.RightElbow, CFrame.Angles(math.rad(-34), 0, 0))
	end
	if motors.LeftElbow then
		setMotorBaseOffset(motors.LeftElbow, CFrame.Angles(math.rad(-72), 0, 0))
	end
	if motors.RightWrist then
		setMotorBaseOffset(motors.RightWrist, CFrame.Angles(math.rad(8) - pitch * 0.35, 0, 0))
	end
	if motors.LeftWrist then
		setMotorBaseOffset(motors.LeftWrist, CFrame.Angles(math.rad(22), 0, math.rad(-8)))
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.new()
		setMotorBaseOffset(motors.Neck, CFrame.Angles(pitch * 0.18, yaw * 0.2, 0))
	end
end

function AnimationManager.ClearPistolPose(model)
	local motors = getAllMotors(model)
	if motors.RightShoulder then
		motors.RightShoulder.Transform = CFrame.new()
		setMotorBaseOffset(motors.RightShoulder, CFrame.new())
	end
	if motors.LeftShoulder then
		motors.LeftShoulder.Transform = CFrame.new()
		setMotorBaseOffset(motors.LeftShoulder, CFrame.new())
	end
	if motors.RightElbow then
		setMotorBaseOffset(motors.RightElbow, CFrame.new())
	end
	if motors.LeftElbow then
		setMotorBaseOffset(motors.LeftElbow, CFrame.new())
	end
	if motors.RightWrist then
		setMotorBaseOffset(motors.RightWrist, CFrame.new())
	end
	if motors.LeftWrist then
		setMotorBaseOffset(motors.LeftWrist, CFrame.new())
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.new()
		setMotorBaseOffset(motors.Neck, CFrame.new())
	end
end

function AnimationManager.PlayDodge(model, moveDir)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RootJoint then return end

	local sideSign = 1
	local preferSidestep = false
	if typeof(moveDir) == "Vector3" and moveDir.Magnitude > 0.05 then
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then
			local localDir = hrp.CFrame:VectorToObjectSpace(moveDir.Unit)
			if math.abs(localDir.X) >= 0.35 then
				sideSign = localDir.X >= 0 and 1 or -1
				preferSidestep = true
			else
				sideSign = localDir.X >= 0 and 1 or -1
			end
		end
	end

	if preferSidestep then
		-- Lateral slip dodge.
		tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-8), math.rad(sideSign * 8), math.rad(-sideSign * 22)), 0.07)
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(8), math.rad(-12), math.rad(sideSign * 25)),
				0.07)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(8), math.rad(12), math.rad(sideSign * 10)),
				0.07)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(18), 0, math.rad(-sideSign * 10)), 0.07)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-6), 0, math.rad(-sideSign * 6)), 0.07)
		end
		queueReset(model, 0.28, 0.18)
	else
		-- Forward roll-like tuck.
		tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(30), math.rad(sideSign * 6), 0), 0.07)
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-58), math.rad(-12), math.rad(24)),
				0.07)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-58), math.rad(12), math.rad(-24)),
				0.07)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(34), 0, 0), 0.07)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(34), 0, 0), 0.07)
		end
		queueReset(model, 0.33, 0.2)
	end
end

-- Hit reaction: MORE DRAMATIC — bigger stagger, spin on heavy hits
function AnimationManager.PlayHitReaction(model, isHeavy)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)

	if isHeavy then
		-- Heavy hit: upper-body recoil only.
		if motors.Neck then
			tweenMotor(motors.Neck, CFrame.new(0, 1.1*s, 0) * CFrame.Angles(math.rad(18), math.rad(-10), math.rad(6)), 0.06)
		end
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(22), math.rad(-6), math.rad(36)),
				0.06)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-6), math.rad(6), math.rad(-42)),
				0.06)
		end
		queueSelectedReset(model, 0.28, 0.22, {"RightShoulder", "LeftShoulder", "Neck"})
	else
		-- Light hit: snap flinch, upper body only.
		if motors.Neck then
			tweenMotor(motors.Neck, CFrame.new(0, 1.1*s, 0) * CFrame.Angles(math.rad(12), 0, math.rad(4)), 0.05)
		end
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(8), 0, math.rad(28)),
				0.05)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(2), 0, math.rad(-30)),
				0.05)
		end
		queueSelectedReset(model, 0.2, 0.18, {"RightShoulder", "LeftShoulder", "Neck"})
	end
end

------------------------------------------------------------
-- ENEMY ANIMATIONS
------------------------------------------------------------

function AnimationManager.PlayThugAttack(model, hitIndex)
	cancelQueuedReset(model)
	local s = 1.0
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	hitIndex = hitIndex or 1
	local isRight = (hitIndex % 2 == 1)
	local shoulder = isRight and motors.RightShoulder or motors.LeftShoulder
	local xSign = isRight and 1 or -1

	if not shoulder then return end

	tweenMotor(shoulder,
		CFrame.new(xSign * 1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-50), math.rad(xSign * 50), math.rad(xSign * 20)),
		0.15)
	if motors.RootJoint then
		tweenMotor(motors.RootJoint, CFrame.Angles(0, math.rad(xSign * 20), 0), 0.15)
	end

	task.delay(0.18, function()
		tweenMotor(shoulder,
			CFrame.new(xSign * 1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-80), math.rad(xSign * -40), math.rad(xSign * -10)),
			0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(0, math.rad(xSign * -20), 0), 0.08)
		end
	end)

	queueReset(model, 0.35, 0.2)
end

function AnimationManager.PlayThugTaunt(model)
	cancelQueuedReset(model)
	local s = 1.0
	local motors = getAllMotors(model)
	if not motors.RightShoulder or not motors.LeftShoulder then return end

	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-70), math.rad(-30), 0),
		0.2)
	tweenMotor(motors.LeftShoulder,
		CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-70), math.rad(30), 0),
		0.2)

	task.delay(0.3, function()
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-60), math.rad(-10), 0),
			0.08, Enum.EasingStyle.Back)
	end)

	task.delay(0.5, function()
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-70), math.rad(-30), 0),
			0.08)
	end)

	task.delay(0.7, function()
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-60), math.rad(-10), 0),
			0.08, Enum.EasingStyle.Back)
	end)

	queueReset(model, 1.0, 0.3)
end

function AnimationManager.PlayBrawlerAttack(model, hitIndex)
	cancelQueuedReset(model)
	local s = 1.3
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	hitIndex = hitIndex or 1

	if hitIndex == 1 then
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(10), math.rad(60), math.rad(40)),
			0.25)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(5), math.rad(40), 0), 0.25)
		end
		task.delay(0.3, function()
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-110), math.rad(-30), math.rad(-20)),
				0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if motors.RootJoint then
				tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-10), math.rad(-40), 0), 0.1)
			end
		end)
		queueReset(model, 0.55, 0.25)

	elseif hitIndex == 2 then
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(15), 0, 0), 0.2)
		end
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-140), 0, math.rad(20)),
			0.2)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-140), 0, math.rad(-20)),
				0.2)
		end
		task.delay(0.25, function()
			if motors.RootJoint then
				tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-25), 0, 0), 0.1, Enum.EasingStyle.Back)
			end
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(10)),
				0.1, Enum.EasingStyle.Back)
			if motors.LeftShoulder then
				tweenMotor(motors.LeftShoulder,
					CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(-10)),
					0.1, Enum.EasingStyle.Back)
			end
		end)
		queueReset(model, 0.5, 0.3)

	elseif hitIndex == 3 then
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(30), 0, 0), 0.15)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(30), 0, 0), 0.15)
		end
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-160), 0, math.rad(15)),
			0.15)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-160), 0, math.rad(-15)),
				0.15)
		end

		task.delay(0.2, function()
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-10), 0, math.rad(5)),
				0.1, Enum.EasingStyle.Back)
			if motors.LeftShoulder then
				tweenMotor(motors.LeftShoulder,
					CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-10), 0, math.rad(-5)),
					0.1, Enum.EasingStyle.Back)
			end
			if motors.RootJoint then
				tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-20), 0, 0), 0.1, Enum.EasingStyle.Back)
			end
			if motors.RightHip then
				tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0), 0.1)
			end
			if motors.LeftHip then
				tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0), 0.1)
			end
		end)

		queueReset(model, 0.5, 0.3)
	end
end

function AnimationManager.PlayBrawlerTaunt(model)
	cancelQueuedReset(model)
	local s = 1.3
	local motors = getAllMotors(model)
	if not motors.RightShoulder or not motors.LeftShoulder then return end

	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(0, 0, math.rad(70)),
		0.2)
	tweenMotor(motors.LeftShoulder,
		CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(0, 0, math.rad(-70)),
		0.2)

	for i = 0, 2 do
		task.delay(0.3 + i * 0.2, function()
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-40), math.rad(-20), math.rad(20)),
				0.08, Enum.EasingStyle.Back)
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-40), math.rad(20), math.rad(-20)),
				0.08, Enum.EasingStyle.Back)
		end)
		task.delay(0.4 + i * 0.2, function()
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(0, 0, math.rad(70)),
				0.08)
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(0, 0, math.rad(-70)),
				0.08)
		end)
	end

	task.delay(1.0, function()
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-60), 0, math.rad(70)),
			0.15)
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-60), 0, math.rad(-70)),
			0.15)
	end)

	queueReset(model, 1.5, 0.3)
end

function AnimationManager.PlaySpeedsterAttack(model, hitIndex)
	cancelQueuedReset(model)
	local s = 0.85
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	hitIndex = hitIndex or 1

	if hitIndex <= 3 then
		local isRight = (hitIndex % 2 == 1)
		local shoulder = isRight and motors.RightShoulder or motors.LeftShoulder
		local otherShoulder = isRight and motors.LeftShoulder or motors.RightShoulder
		local xSign = isRight and 1 or -1

		if shoulder then
			tweenMotor(shoulder,
				CFrame.new(xSign * 1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-95), 0, 0),
				0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		if otherShoulder then
			tweenMotor(otherShoulder,
				CFrame.new(-xSign * 1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-40), 0, math.rad(-xSign * 15)),
				0.05)
		end
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(0, math.rad(xSign * -8), 0), 0.05)
		end

		queueReset(model, 0.1, 0.06)

	elseif hitIndex == 4 then
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-10), math.rad(-45), 0), 0.08)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-90), 0, math.rad(30)),
				0.08, Enum.EasingStyle.Back)
		end
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(10), 0, math.rad(40)),
			0.08)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(10), 0, math.rad(-40)),
				0.08)
		end

		task.delay(0.1, function()
			if motors.RootJoint then
				tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-10), math.rad(45), 0), 0.1)
			end
		end)

		queueReset(model, 0.3, 0.2)
	end
end

function AnimationManager.PlaySpeedsterTaunt(model)
	cancelQueuedReset(model)
	local s = 0.85
	local motors = getAllMotors(model)
	if not motors.RightShoulder or not motors.LeftShoulder then return end

	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-75), math.rad(-20), math.rad(10)),
		0.1)
	tweenMotor(motors.LeftShoulder,
		CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-85), math.rad(15), math.rad(-10)),
		0.1)

	for i = 0, 4 do
		task.delay(0.15 + i * 0.15, function()
			local hip = (i % 2 == 0) and motors.RightHip or motors.LeftHip
			local otherHip = (i % 2 == 0) and motors.LeftHip or motors.RightHip
			local xSign = (i % 2 == 0) and 1 or -1
			if hip then
				tweenMotor(hip,
					CFrame.new(xSign * 0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-15), 0, 0),
					0.07)
			end
			if otherHip then
				tweenMotor(otherHip,
					CFrame.new(-xSign * 0.5*s, -1*s, 0) * CFrame.Angles(math.rad(10), 0, 0),
					0.07)
			end
		end)
	end

	queueReset(model, 1.0, 0.2)
end

------------------------------------------------------------
-- LOCOMOTION (direct C0 — no tweens for smooth continuous motion)
------------------------------------------------------------
function AnimationManager.PlayEnemyLocomotion(model, enemyType, isMoving)
	local motors = getAllMotors(model)
	if not motors.RightShoulder or not motors.LeftShoulder then return end

	local s = 1
	if enemyType == "Brawler" then
		s = 1.15
	elseif enemyType == "Speedster" then
		s = 0.9
	end

	if isMoving then
		local t = tick()
		local armSwing = math.sin(t * 8) * math.rad(35)
		local legSwing = math.sin(t * 8) * math.rad(28)
		local bodyBob = math.sin(t * 16) * math.rad(2)

		setMotorDirect(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(-armSwing, 0, math.rad(5)))
		setMotorDirect(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(armSwing, 0, math.rad(-5)))

		if motors.RightHip then
			setMotorDirect(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(legSwing, 0, 0))
		end
		if motors.LeftHip then
			setMotorDirect(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(-legSwing, 0, 0))
		end
		if motors.RootJoint then
			setMotorDirect(motors.RootJoint,
				CFrame.Angles(math.rad(-3), 0, bodyBob))
		end
	else
		-- Idle: subtle breathing sway
		local t = tick()
		local breathe = math.sin(t * 2) * math.rad(3)

		setMotorDirect(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(breathe, 0, math.rad(3)))
		setMotorDirect(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(-breathe, 0, math.rad(-3)))

		if motors.RightHip then
			setMotorDirect(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0))
		end
		if motors.LeftHip then
			setMotorDirect(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0))
		end
		if motors.RootJoint then
			setMotorDirect(motors.RootJoint,
				CFrame.Angles(0, 0, breathe * 0.5))
		end
	end
end

-- Player locomotion — similar but slightly different proportions
function AnimationManager.PlayPlayerLocomotion(model, isMoving, isSprinting)
	local motors = getAllMotors(model)
	if not motors.RightShoulder or not motors.LeftShoulder then return end

	local s = 1

	if isMoving then
		local speed = isSprinting and 11 or 8
		local amplitude = isSprinting and 42 or 30
		local t = tick()
		local armSwing = math.sin(t * speed) * math.rad(amplitude)
		local legSwing = math.sin(t * speed) * math.rad(amplitude * 0.8)
		local bodyBob = math.sin(t * speed * 2) * math.rad(2)

		setMotorDirect(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(-armSwing, 0, math.rad(5)))
		setMotorDirect(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(armSwing, 0, math.rad(-5)))

		if motors.RightHip then
			setMotorDirect(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(legSwing, 0, 0))
		end
		if motors.LeftHip then
			setMotorDirect(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(-legSwing, 0, 0))
		end
		if motors.RootJoint then
			setMotorDirect(motors.RootJoint,
				CFrame.Angles(isSprinting and math.rad(-8) or math.rad(-3), 0, bodyBob))
		end
	else
		-- Idle breathing
		local t = tick()
		local breathe = math.sin(t * 2) * math.rad(2)

		setMotorDirect(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(breathe, 0, math.rad(3)))
		setMotorDirect(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(-breathe, 0, math.rad(-3)))

		if motors.RightHip then
			setMotorDirect(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0))
		end
		if motors.LeftHip then
			setMotorDirect(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(0, 0, 0))
		end
		if motors.RootJoint then
			setMotorDirect(motors.RootJoint,
				CFrame.Angles(0, 0, breathe * 0.3))
		end
	end
end

------------------------------------------------------------
-- TAUNT BILLBOARD TEXT
------------------------------------------------------------
function AnimationManager.ShowTauntText(model, text, duration)
	duration = duration or 2
	if not model or not model.PrimaryPart then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TauntText"
	billboard.Size = UDim2.new(8, 0, 2, 0)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 50)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard

	label.TextTransparency = 1
	label.TextStrokeTransparency = 1

	local ts = game:GetService("TweenService")
	ts:Create(label, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
		TextTransparency = 0,
		TextStrokeTransparency = 0
	}):Play()

	task.delay(duration - 0.3, function()
		if label and label.Parent then
			ts:Create(label, TweenInfo.new(0.3), {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			}):Play()
		end
	end)

	task.delay(duration, function()
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	end)
end

return AnimationManager
