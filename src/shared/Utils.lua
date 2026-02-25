-- Utils: Shared utility functions
local Utils = {}

local function createWeldedPart(model, parentPart, name, size, offset, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = parentPart.CFrame * offset
	part.BrickColor = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parentPart
	weld.Part1 = part
	weld.Parent = part

	return part
end

local function applyEnemyStyle(model, enemyType, torso, head, leftArm, rightArm, leftLeg, rightLeg, scaleMultiplier)
	local s = scaleMultiplier or 1
	enemyType = enemyType or model.Name
	if not torso or not head then return end

	if enemyType == "Thug" then
		torso.BrickColor = BrickColor.new("Black")
		torso.Material = Enum.Material.Fabric
		if leftArm then leftArm.BrickColor = BrickColor.new("Smoky grey") end
		if rightArm then rightArm.BrickColor = BrickColor.new("Smoky grey") end
		if leftLeg then leftLeg.BrickColor = BrickColor.new("Really black") end
		if rightLeg then rightLeg.BrickColor = BrickColor.new("Really black") end
		if head:IsA("Part") then
			head.Shape = Enum.PartType.Block
		end
		head.BrickColor = BrickColor.new("Pastel brown")

		createWeldedPart(
			model,
			torso,
			"JacketLayer",
			Vector3.new(2.2 * s, 2.2 * s, 1.15 * s),
			CFrame.new(0, 0, 0),
			BrickColor.new("Dark stone grey"),
			Enum.Material.Fabric
		)
		createWeldedPart(
			model,
			head,
			"Beanie",
			Vector3.new(1.3 * s, 0.35 * s, 1.3 * s),
			CFrame.new(0, 0.5 * s, 0),
			BrickColor.new("Really black"),
			Enum.Material.Fabric
		)
	elseif enemyType == "Brawler" then
		torso.BrickColor = BrickColor.new("Reddish brown")
		torso.Material = Enum.Material.Metal
		if leftArm then leftArm.BrickColor = BrickColor.new("Dark orange") end
		if rightArm then rightArm.BrickColor = BrickColor.new("Dark orange") end
		if leftLeg then leftLeg.BrickColor = BrickColor.new("Brown") end
		if rightLeg then rightLeg.BrickColor = BrickColor.new("Brown") end
		if head:IsA("Part") then
			head.Shape = Enum.PartType.Block
		end
		head.BrickColor = BrickColor.new("Brown")

		createWeldedPart(
			model,
			torso,
			"ChestPlate",
			Vector3.new(2.25 * s, 1.1 * s, 0.35 * s),
			CFrame.new(0, 0.35 * s, -0.65 * s),
			BrickColor.new("Really black"),
			Enum.Material.Metal
		)
		if leftArm then
			createWeldedPart(
				model,
				leftArm,
				"LeftShoulderPad",
				Vector3.new(0.9 * s, 0.5 * s, 0.9 * s),
				CFrame.new(0, 0.85 * s, 0),
				BrickColor.new("Black"),
				Enum.Material.Metal
			)
		end
		if rightArm then
			createWeldedPart(
				model,
				rightArm,
				"RightShoulderPad",
				Vector3.new(0.9 * s, 0.5 * s, 0.9 * s),
				CFrame.new(0, 0.85 * s, 0),
				BrickColor.new("Black"),
				Enum.Material.Metal
			)
		end
	elseif enemyType == "Speedster" then
		torso.BrickColor = BrickColor.new("Institutional white")
		torso.Material = Enum.Material.SmoothPlastic
		if leftArm then leftArm.BrickColor = BrickColor.new("New Yeller") end
		if rightArm then rightArm.BrickColor = BrickColor.new("New Yeller") end
		if leftLeg then leftLeg.BrickColor = BrickColor.new("Really black") end
		if rightLeg then rightLeg.BrickColor = BrickColor.new("Really black") end
		head.BrickColor = BrickColor.new("Pastel yellow")

		createWeldedPart(
			model,
			torso,
			"SpeedStripe",
			Vector3.new(2.15 * s, 0.35 * s, 0.2 * s),
			CFrame.new(0, 0.1 * s, -0.6 * s),
			BrickColor.new("Really red"),
			Enum.Material.Neon
		)
		createWeldedPart(
			model,
			head,
			"Visor",
			Vector3.new(1.0 * s, 0.4 * s, 0.2 * s),
			CFrame.new(0, 0.1 * s, -0.55 * s),
			BrickColor.new("Cyan"),
			Enum.Material.Neon
		)
	end
end

-- Create a humanoid NPC model from scratch (R15 rig via CharacterBuilder)
function Utils.CreateNPCModel(name, position, color, scaleMultiplier, enemyType)
	scaleMultiplier = scaleMultiplier or 1
	local s = math.max(0.7, scaleMultiplier)

	local CharacterBuilder = require(script.Parent:WaitForChild("CharacterBuilder"))
	local model = CharacterBuilder.Build(name, position, color, s)

	-- Apply cosmetic enemy style overlays
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso")
	local head = model:FindFirstChild("Head")
	local leftArm = model:FindFirstChild("LeftUpperArm")
	local rightArm = model:FindFirstChild("RightUpperArm")
	local leftLeg = model:FindFirstChild("LeftUpperLeg")
	local rightLeg = model:FindFirstChild("RightUpperLeg")

	applyEnemyStyle(model, enemyType, torso, head, leftArm, rightArm, leftLeg, rightLeg, s)

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
