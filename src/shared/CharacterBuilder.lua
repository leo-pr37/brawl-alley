--[[
	CharacterBuilder (Shared)
	Builds proper R15 humanoid rigs from code.
	Each NPC gets 16 parts and 15 Motor6D joints so the Humanoid
	detects RigType == R15 and Roblox plays R15 walk/idle animations.
]]

local CharacterBuilder = {}

------------------------------------------------------------
-- R15 PART DEFINITIONS  {name, size, offset_from_HRP}
------------------------------------------------------------
local function scaledParts(s)
	return {
		{"HumanoidRootPart", Vector3.new(2*s, 2*s, 1*s),   Vector3.new(0, 0, 0)},
		{"LowerTorso",       Vector3.new(1.5*s, 0.5*s, 1*s), Vector3.new(0, -0.75*s, 0)},
		{"UpperTorso",       Vector3.new(1.8*s, 1.2*s, 1*s), Vector3.new(0, 0.35*s, 0)},
		{"Head",             Vector3.new(1.2*s, 1.2*s, 1.2*s), Vector3.new(0, 1.55*s, 0)},

		{"LeftUpperArm",     Vector3.new(0.6*s, 1.0*s, 0.6*s), Vector3.new(-1.4*s, 0.25*s, 0)},
		{"LeftLowerArm",     Vector3.new(0.55*s, 1.0*s, 0.55*s), Vector3.new(-1.4*s, -0.75*s, 0)},
		{"LeftHand",         Vector3.new(0.5*s, 0.35*s, 0.5*s), Vector3.new(-1.4*s, -1.45*s, 0)},

		{"RightUpperArm",    Vector3.new(0.6*s, 1.0*s, 0.6*s), Vector3.new(1.4*s, 0.25*s, 0)},
		{"RightLowerArm",    Vector3.new(0.55*s, 1.0*s, 0.55*s), Vector3.new(1.4*s, -0.75*s, 0)},
		{"RightHand",        Vector3.new(0.5*s, 0.35*s, 0.5*s), Vector3.new(1.4*s, -1.45*s, 0)},

		{"LeftUpperLeg",     Vector3.new(0.65*s, 1.0*s, 0.65*s), Vector3.new(-0.5*s, -1.5*s, 0)},
		{"LeftLowerLeg",     Vector3.new(0.6*s, 1.0*s, 0.6*s), Vector3.new(-0.5*s, -2.5*s, 0)},
		{"LeftFoot",         Vector3.new(0.6*s, 0.35*s, 1*s), Vector3.new(-0.5*s, -3.2*s, 0)},

		{"RightUpperLeg",    Vector3.new(0.65*s, 1.0*s, 0.65*s), Vector3.new(0.5*s, -1.5*s, 0)},
		{"RightLowerLeg",    Vector3.new(0.6*s, 1.0*s, 0.6*s), Vector3.new(0.5*s, -2.5*s, 0)},
		{"RightFoot",        Vector3.new(0.6*s, 0.35*s, 1*s), Vector3.new(0.5*s, -3.2*s, 0)},
	}
end

------------------------------------------------------------
-- R15 MOTOR6D DEFINITIONS  {name, part0, part1, C0, C1}
------------------------------------------------------------
local function scaledJoints(s)
	return {
		{"Root",           "HumanoidRootPart", "LowerTorso",
			CFrame.new(0, -0.75*s, 0), CFrame.new(0, 0, 0)},
		{"Waist",          "LowerTorso", "UpperTorso",
			CFrame.new(0, 0.25*s, 0),  CFrame.new(0, -0.6*s, 0)},
		{"Neck",           "UpperTorso", "Head",
			CFrame.new(0, 0.6*s, 0),   CFrame.new(0, -0.5*s, 0)},

		{"RightShoulder",  "UpperTorso", "RightUpperArm",
			CFrame.new(1*s, 0.4*s, 0),  CFrame.new(-0.4*s, 0.4*s, 0)},
		{"RightElbow",     "RightUpperArm", "RightLowerArm",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.5*s, 0)},
		{"RightWrist",     "RightLowerArm", "RightHand",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.175*s, 0)},

		{"LeftShoulder",   "UpperTorso", "LeftUpperArm",
			CFrame.new(-1*s, 0.4*s, 0), CFrame.new(0.4*s, 0.4*s, 0)},
		{"LeftElbow",      "LeftUpperArm", "LeftLowerArm",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.5*s, 0)},
		{"LeftWrist",      "LeftLowerArm", "LeftHand",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.175*s, 0)},

		{"RightHip",       "LowerTorso", "RightUpperLeg",
			CFrame.new(0.5*s, -0.25*s, 0), CFrame.new(0, 0.5*s, 0)},
		{"RightKnee",      "RightUpperLeg", "RightLowerLeg",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.5*s, 0)},
		{"RightAnkle",     "RightLowerLeg", "RightFoot",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.175*s, 0)},

		{"LeftHip",        "LowerTorso", "LeftUpperLeg",
			CFrame.new(-0.5*s, -0.25*s, 0), CFrame.new(0, 0.5*s, 0)},
		{"LeftKnee",       "LeftUpperLeg", "LeftLowerLeg",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.5*s, 0)},
		{"LeftAnkle",      "LeftLowerLeg", "LeftFoot",
			CFrame.new(0, -0.5*s, 0),  CFrame.new(0, 0.175*s, 0)},
	}
end

------------------------------------------------------------
-- BUILD
------------------------------------------------------------
function CharacterBuilder.Build(name, position, color, scaleMultiplier)
	local s = math.max(0.7, scaleMultiplier or 1)
	local model = Instance.new("Model")
	model.Name = name

	local parts = {}
	local baseCF = CFrame.new(position) + Vector3.new(0, 3.5 * s, 0)

	-- Create all parts
	for _, def in ipairs(scaledParts(s)) do
		local partName, size, offset = def[1], def[2], def[3]
		local part = Instance.new("Part")
		part.Name = partName
		part.Size = size
		part.CFrame = baseCF + offset
		part.Anchored = false
		part.CanCollide = (partName == "LeftFoot" or partName == "RightFoot" or partName == "LeftLowerLeg" or partName == "RightLowerLeg")
		part.Material = Enum.Material.SmoothPlastic
		part.BrickColor = color or BrickColor.new("Medium stone grey")

		if partName == "HumanoidRootPart" then
			part.Transparency = 1
			part.CanCollide = false
		elseif partName == "Head" then
			part.Shape = Enum.PartType.Ball
			-- Face decal
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Face = Enum.NormalId.Front
			face.Texture = "rbxasset://textures/face.png"
			face.Parent = part
		end

		part.Parent = model
		parts[partName] = part
	end

	-- Create Motor6D joints
	for _, def in ipairs(scaledJoints(s)) do
		local jointName, p0Name, p1Name, c0, c1 = def[1], def[2], def[3], def[4], def[5]
		local motor = Instance.new("Motor6D")
		motor.Name = jointName
		motor.Part0 = parts[p0Name]
		motor.Part1 = parts[p1Name]
		motor.C0 = c0
		motor.C1 = c1
		motor.Parent = parts[p0Name]
	end

	-- Add Humanoid (after rig is built so RigType detects R15)
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.HipHeight = 2 * s
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayDistance = 50
	humanoid.NameDisplayDistance = 50
	humanoid.Parent = model

	model.PrimaryPart = parts["HumanoidRootPart"]
	return model
end

return CharacterBuilder
