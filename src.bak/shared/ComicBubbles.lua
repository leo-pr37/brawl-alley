--[[
	ComicBubbles (Shared/Client)
	Comic book style hit effect bubbles: "POW!", "BAM!", "WHAM!", etc.
	Creates BillboardGui with bold comic text, burst shape, scale tweens.
]]

local TweenService = game:GetService("TweenService")

local ComicBubbles = {}

-- Word pools
local LIGHT_WORDS = {"BAM!", "BONK!", "ZAP!", "WHAM!", "SMASH!"}
local HEAVY_WORDS = {"CRACK!", "SMASH!", "KAPOW!", "WHAM!"}
local COMBO_WORDS = {"KAPOW!", "SMASH!", "WHAM!", "CRACK!", "BAM!"}
local UPPERCUT_WORD = "POW!"

-- Colors for burst backgrounds
local BURST_COLORS = {
	Color3.fromRGB(255, 220, 0),   -- yellow
	Color3.fromRGB(255, 80, 30),   -- orange-red
	Color3.fromRGB(255, 50, 50),   -- red
	Color3.fromRGB(255, 150, 0),   -- orange
	Color3.fromRGB(0, 200, 255),   -- cyan (for variety)
}

-- Size presets
local SIZES = {
	light  = {gui = UDim2.new(4, 0, 2.5, 0), textSize = 36, studsOffset = Vector3.new(0, 3, 0)},
	heavy  = {gui = UDim2.new(6, 0, 3.5, 0), textSize = 48, studsOffset = Vector3.new(0, 4, 0)},
	combo  = {gui = UDim2.new(8, 0, 5, 0),   textSize = 60, studsOffset = Vector3.new(0, 5, 0)},
	uppercut = {gui = UDim2.new(7, 0, 4.5, 0), textSize = 56, studsOffset = Vector3.new(0, 6, 0)},
}

local function pickRandom(tbl)
	return tbl[math.random(1, #tbl)]
end

-- Create a comic bubble at a world position (attached to a part or adornee)
-- hitType: "light", "heavy", "combo", "uppercut"
function ComicBubbles.Spawn(adornee, hitType, worldPosition)
	hitType = hitType or "light"
	local sizeInfo = SIZES[hitType] or SIZES.light

	-- Pick word
	local word
	if hitType == "uppercut" then
		word = UPPERCUT_WORD
	elseif hitType == "combo" then
		word = pickRandom(COMBO_WORDS)
	elseif hitType == "heavy" then
		word = pickRandom(HEAVY_WORDS)
	else
		word = pickRandom(LIGHT_WORDS)
	end

	local burstColor = pickRandom(BURST_COLORS)
	local rotation = math.random(-15, 15)

	-- Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ComicBubble"
	billboard.Size = sizeInfo.gui
	billboard.StudsOffset = sizeInfo.studsOffset + Vector3.new(math.random(-10, 10) * 0.1, math.random(-5, 5) * 0.1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100

	if adornee and adornee:IsA("BasePart") then
		billboard.Adornee = adornee
		billboard.Parent = adornee.Parent or workspace
	elseif worldPosition then
		-- Create anchor part
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Position = worldPosition
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Parent = workspace
		billboard.Adornee = anchor
		billboard.Parent = workspace
		-- Clean up anchor later
		task.delay(1, function()
			if anchor and anchor.Parent then anchor:Destroy() end
		end)
	else
		billboard:Destroy()
		return
	end

	-- Container frame for rotation
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.Rotation = rotation
	container.Parent = billboard

	-- Burst background (star/explosion shape via ImageLabel or colored frame)
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.Size = UDim2.new(0.9, 0, 0.85, 0)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.new(0.5, 0, 0.5, 0)
	burst.BackgroundColor3 = burstColor
	burst.BorderSizePixel = 0
	burst.Parent = container

	local burstCorner = Instance.new("UICorner")
	burstCorner.CornerRadius = UDim.new(0.2, 0)
	burstCorner.Parent = burst

	-- Black outline stroke
	local burstStroke = Instance.new("UIStroke")
	burstStroke.Color = Color3.new(0, 0, 0)
	burstStroke.Thickness = 4
	burstStroke.Parent = burst

	-- Inner white border
	local inner = Instance.new("Frame")
	inner.Size = UDim2.new(0.92, 0, 0.88, 0)
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.BackgroundColor3 = Color3.new(1, 1, 1)
	inner.BackgroundTransparency = 0.15
	inner.BorderSizePixel = 0
	inner.Parent = burst

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0.15, 0)
	innerCorner.Parent = inner

	-- Comic text
	local label = Instance.new("TextLabel")
	label.Name = "ComicText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text = word
	label.TextColor3 = Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = burstColor
	label.Parent = burst

	-- Stars around uppercut
	if hitType == "uppercut" then
		for i = 1, 4 do
			local star = Instance.new("TextLabel")
			star.Size = UDim2.new(0.15, 0, 0.15, 0)
			star.BackgroundTransparency = 1
			star.Text = "★"
			star.TextColor3 = Color3.fromRGB(255, 255, 0)
			star.Font = Enum.Font.GothamBlack
			star.TextScaled = true
			star.TextStrokeTransparency = 0
			star.TextStrokeColor3 = Color3.fromRGB(200, 100, 0)
			local angle = (i / 4) * math.pi * 2
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Position = UDim2.new(0.5 + math.cos(angle) * 0.45, 0, 0.5 + math.sin(angle) * 0.4, 0)
			star.Parent = container
		end
	end

	-- Scale tween: 0 → 1.2 → 1.0 over 0.2s, then fade over 0.3s
	-- Start at scale 0
	container.Size = UDim2.new(0, 0, 0, 0)

	-- Phase 1: scale to 1.2
	local tweenGrow = TweenService:Create(container, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1.2, 0, 1.2, 0)
	})
	tweenGrow:Play()

	task.delay(0.12, function()
		-- Phase 2: settle to 1.0
		local tweenSettle = TweenService:Create(container, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		})
		tweenSettle:Play()
	end)

	-- Phase 3: float up slightly and fade out
	task.delay(0.2, function()
		if not billboard or not billboard.Parent then return end
		-- Fade out over 0.3s
		local currentOffset = billboard.StudsOffset
		TweenService:Create(billboard, TweenInfo.new(0.3), {
			StudsOffset = currentOffset + Vector3.new(0, 1.5, 0)
		}):Play()

		-- Fade all text
		for _, desc in ipairs(billboard:GetDescendants()) do
			if desc:IsA("TextLabel") then
				TweenService:Create(desc, TweenInfo.new(0.3), {
					TextTransparency = 1,
					TextStrokeTransparency = 1
				}):Play()
			elseif desc:IsA("Frame") then
				TweenService:Create(desc, TweenInfo.new(0.3), {
					BackgroundTransparency = 1
				}):Play()
			elseif desc:IsA("UIStroke") then
				TweenService:Create(desc, TweenInfo.new(0.3), {
					Transparency = 1
				}):Play()
			end
		end
	end)

	-- Cleanup
	task.delay(0.6, function()
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	end)
end

return ComicBubbles
