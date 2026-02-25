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
	LeftShoulder  = CFrame.new(-1.3, 0.5, 0) * CFrame.Angles(0, 0, 0),
	RightHip      = CFrame.new(0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	LeftHip       = CFrame.new(-0.5, -1, 0) * CFrame.Angles(0, 0, 0),
	Neck          = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, 0),
	RootJoint     = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0),
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
		-- Jab: right arm forward punch with more body twist
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-95), 0, math.rad(-5)),
			0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-35), 0, math.rad(20)),
				0.07)
		end
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-5), math.rad(-20), 0), 0.07)
		end
		-- Front foot steps
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-10), 0, 0), 0.07)
		end
		queueReset(model, 0.15, 0.12)

	elseif comboIndex == 2 then
		-- Cross: left arm with big twist
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-95), 0, math.rad(5)),
				0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-35), 0, math.rad(-20)),
			0.07)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-5), math.rad(25), 0), 0.07)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-10), 0, 0), 0.07)
		end
		queueReset(model, 0.15, 0.12)

	elseif comboIndex == 3 then
		-- Hook: dramatic side swing with full body rotation
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-75), math.rad(-70), math.rad(25)),
			0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-8), math.rad(-35), math.rad(-5)), 0.05)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-20), 0, 0),
				0.05)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(25)),
				0.05)
		end
		queueReset(model, 0.18, 0.15)

	elseif comboIndex == 4 then
		-- UPPERCUT: BIG wind down then explosive upward (player also jumps via CombatController)
		-- Wind down: deep crouch
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(40), 0, math.rad(-15)),
			0.06)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(20), 0, 0), 0.06)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(30), 0, 0), 0.06)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(30), 0, 0), 0.06)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(20), 0, math.rad(15)),
				0.06)
		end

		task.delay(0.07, function()
			-- EXPLODE upward — maximum extension
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-170), math.rad(15), math.rad(-15)),
				0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if motors.RootJoint then
				tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-20), math.rad(-20), math.rad(-5)), 0.07)
			end
			if motors.LeftShoulder then
				tweenMotor(motors.LeftShoulder,
					CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-40), 0, math.rad(-20)),
					0.07)
			end
			if motors.RightHip then
				tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-10), 0, 0), 0.07)
			end
			if motors.LeftHip then
				tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-10), 0, 0), 0.07)
			end
		end)

		queueReset(model, 0.3, 0.25)
	end
end

-- Heavy punch - BIGGER wind-up, more dramatic forward lunge
function AnimationManager.PlayHeavyPunch(model)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	-- Wind-up: pull arm WAY back, lean back dramatically
	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(30), math.rad(50), math.rad(40)),
		0.18)
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-50), 0, math.rad(25)),
			0.18)
	end
	if motors.RootJoint then
		tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(10), math.rad(40), math.rad(5)), 0.18)
	end
	-- Lean back on legs
	if motors.RightHip then
		tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(15), 0, 0), 0.18)
	end
	if motors.LeftHip then
		tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-5), 0, 0), 0.18)
	end

	task.delay(0.2, function()
		-- SLAM forward with maximum force
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-110), math.rad(-25), math.rad(-15)),
			0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(10), 0, math.rad(-10)),
				0.07)
		end
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-15), math.rad(-40), math.rad(-5)), 0.07)
		end
		-- Big step forward
		if motors.LeftHip then
			tweenMotor(motors.LeftHip,
				CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-30), 0, 0),
				0.07)
		end
		if motors.RightHip then
			tweenMotor(motors.RightHip,
				CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(15), 0, 0),
				0.07)
		end
	end)

	queueReset(model, 0.45, 0.3)
end

function AnimationManager.PlayBlock(model)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RightShoulder then return end

	tweenMotor(motors.RightShoulder,
		CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-80), math.rad(-30), math.rad(20)),
		0.1)
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-80), math.rad(30), math.rad(-20)),
			0.1)
	end
	if motors.RightHip then
		tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(10), 0, 0), 0.1)
	end
	if motors.LeftHip then
		tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(10), 0, 0), 0.1)
	end
end

function AnimationManager.PlayUnblock(model)
	AnimationManager.ResetPose(model, 0.15)
end

function AnimationManager.PlayDodge(model)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)
	if not motors.RootJoint then return end

	tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(-15), 0, math.rad(25)), 0.08)
	if motors.RightShoulder then
		tweenMotor(motors.RightShoulder,
			CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(30)),
			0.08)
	end
	if motors.LeftShoulder then
		tweenMotor(motors.LeftShoulder,
			CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(-30)),
			0.08)
	end
	if motors.RightHip then
		tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(25), 0, 0), 0.08)
	end
	if motors.LeftHip then
		tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(25), 0, 0), 0.08)
	end

	queueReset(model, 0.35, 0.2)
end

-- Hit reaction: MORE DRAMATIC — bigger stagger, spin on heavy hits
function AnimationManager.PlayHitReaction(model, isHeavy)
	cancelQueuedReset(model)
	local s = 1
	local motors = getAllMotors(model)

	if isHeavy then
		-- Heavy hit: dramatic spin/stagger
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(25), math.rad(45), math.rad(10)), 0.06)
		end
		if motors.Neck then
			tweenMotor(motors.Neck, CFrame.new(0, 1.1*s, 0) * CFrame.Angles(math.rad(25), math.rad(-20), math.rad(10)), 0.06)
		end
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(15), 0, math.rad(50)),
				0.06)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-15), 0, math.rad(-50)),
				0.06)
		end
		-- Stagger legs
		if motors.RightHip then
			tweenMotor(motors.RightHip, CFrame.new(0.5*s, -1*s, 0) * CFrame.Angles(math.rad(-15), math.rad(10), 0), 0.06)
		end
		if motors.LeftHip then
			tweenMotor(motors.LeftHip, CFrame.new(-0.5*s, -1*s, 0) * CFrame.Angles(math.rad(20), 0, 0), 0.06)
		end
		queueReset(model, 0.35, 0.3)
	else
		-- Light hit: snap backward flinch (enhanced)
		if motors.RootJoint then
			tweenMotor(motors.RootJoint, CFrame.Angles(math.rad(18), math.rad(8), math.rad(5)), 0.05)
		end
		if motors.Neck then
			tweenMotor(motors.Neck, CFrame.new(0, 1.1*s, 0) * CFrame.Angles(math.rad(18), 0, math.rad(5)), 0.05)
		end
		if motors.RightShoulder then
			tweenMotor(motors.RightShoulder,
				CFrame.new(1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-10), 0, math.rad(40)),
				0.05)
		end
		if motors.LeftShoulder then
			tweenMotor(motors.LeftShoulder,
				CFrame.new(-1.3*s, 0.5*s, 0) * CFrame.Angles(math.rad(-10), 0, math.rad(-40)),
				0.05)
		end
		queueReset(model, 0.2, 0.2)
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
