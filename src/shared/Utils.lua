-- Utils: Shared utility functions
local Utils = {}

-- Create a humanoid NPC model from scratch
function Utils.CreateNPCModel(name, position, color, scaleMultiplier)
	scaleMultiplier = scaleMultiplier or 1
	local s = scaleMultiplier

	local model = Instance.new("Model")
	model.Name = name

	-- Torso (HumanoidRootPart)
	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = Vector3.new(2 * s, 2 * s, 1 * s)
	torso.CFrame = CFrame.new(position) + Vector3.new(0, 3 * s, 0)
	torso.BrickColor = color
	torso.Anchored = false
	torso.CanCollide = true
	torso.Material = Enum.Material.SmoothPlastic
	torso.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2 * s, 1.2 * s, 1.2 * s)
	head.CFrame = torso.CFrame + Vector3.new(0, 1.6 * s, 0)
	head.BrickColor = BrickColor.new("Light orange")
	head.Anchored = false
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head

	-- Face on head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	-- Left Arm
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(0.6 * s, 2 * s, 0.6 * s)
	leftArm.CFrame = torso.CFrame + Vector3.new(-1.3 * s, 0, 0)
	leftArm.BrickColor = color
	leftArm.Anchored = false
	leftArm.CanCollide = false
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.Parent = model

	local laWeld = Instance.new("WeldConstraint")
	laWeld.Part0 = torso
	laWeld.Part1 = leftArm
	laWeld.Parent = leftArm

	-- Right Arm
	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(0.6 * s, 2 * s, 0.6 * s)
	rightArm.CFrame = torso.CFrame + Vector3.new(1.3 * s, 0, 0)
	rightArm.BrickColor = color
	rightArm.Anchored = false
	rightArm.CanCollide = false
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.Parent = model

	local raWeld = Instance.new("WeldConstraint")
	raWeld.Part0 = torso
	raWeld.Part1 = rightArm
	raWeld.Parent = rightArm

	-- Left Leg
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(0.7 * s, 2 * s, 0.7 * s)
	leftLeg.CFrame = torso.CFrame + Vector3.new(-0.5 * s, -2 * s, 0)
	leftLeg.BrickColor = BrickColor.new("Dark stone grey")
	leftLeg.Anchored = false
	leftLeg.CanCollide = false
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.Parent = model

	local llWeld = Instance.new("WeldConstraint")
	llWeld.Part0 = torso
	llWeld.Part1 = leftLeg
	llWeld.Parent = leftLeg

	-- Right Leg
	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(0.7 * s, 2 * s, 0.7 * s)
	rightLeg.CFrame = torso.CFrame + Vector3.new(0.5 * s, -2 * s, 0)
	rightLeg.BrickColor = BrickColor.new("Dark stone grey")
	rightLeg.Anchored = false
	rightLeg.CanCollide = false
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.Parent = model

	local rlWeld = Instance.new("WeldConstraint")
	rlWeld.Part0 = torso
	rlWeld.Part1 = rightLeg
	rlWeld.Parent = rightLeg

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayDistance = 50
	humanoid.NameDisplayDistance = 50

	model.PrimaryPart = torso
	return model
end

-- Create a billboard health bar above a model
function Utils.CreateHealthBar(model, maxHealth)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.3, 0)
	fillCorner.Parent = fill

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = model.Name
	nameLabel.Parent = bg

	return billboard
end

-- Lerp Color3
function Utils.LerpColor(a, b, t)
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

-- Distance between two positions (XZ plane only for ground combat)
function Utils.GroundDistance(pos1, pos2)
	local dx = pos1.X - pos2.X
	local dz = pos1.Z - pos2.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Get all enemies in range of a position
function Utils.GetEnemiesInRange(position, range, enemiesFolder)
	local results = {}
	if not enemiesFolder then return results end
	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local dist = (enemy.PrimaryPart.Position - position).Magnitude
			if dist <= range then
				table.insert(results, enemy)
			end
		end
	end
	return results
end

return Utils
