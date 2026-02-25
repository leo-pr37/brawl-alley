--[[
	DevPanel (Client)
	Toggle with F9 or backtick (`).
	Debug panel for testing animations, spawning enemies, god mode, etc.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))

-- Wait for dev remotes
local DevFreezeEvent = ReplicatedStorage:WaitForChild("DevFreezeEnemies", 10)
local DevKillAllEvent = ReplicatedStorage:WaitForChild("DevKillAll", 10)
local DevSpawnEnemyEvent = ReplicatedStorage:WaitForChild("DevSpawnEnemy", 10)
local DevTriggerTauntEvent = ReplicatedStorage:WaitForChild("DevTriggerTaunt", 10)
local DevTriggerComboEvent = ReplicatedStorage:WaitForChild("DevTriggerCombo", 10)
local DevGodModeEvent = ReplicatedStorage:WaitForChild("DevGodMode", 10)
local DevSpawnWaveEvent = ReplicatedStorage:WaitForChild("DevSpawnWave", 10)

-- State
local panelOpen = false
local freezeOn = false
local godModeOn = false

------------------------------------------------------------
-- UI CREATION
------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevPanelUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

-- Full-screen backdrop (captures mouse so it can move freely)
local backdrop = Instance.new("TextButton")
backdrop.Name = "DevBackdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.Position = UDim2.new(0, 0, 0, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.7
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Visible = false
backdrop.ZIndex = 49
backdrop.Parent = screenGui

-- Click backdrop to close panel (connected after togglePanel is defined below)

-- Main panel frame (right side)
local panel = Instance.new("ScrollingFrame")
panel.Name = "DevPanel"
panel.Size = UDim2.new(0, 280, 0.85, 0)
panel.Position = UDim2.new(1, -290, 0.075, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 6
panel.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
panel.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-set later
panel.Visible = false
panel.ZIndex = 50
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(80, 80, 100)
panelStroke.Thickness = 2
panelStroke.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = panel

-- Auto-resize canvas
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	panel.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
end)

------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------
local layoutOrder = 0

local function nextOrder()
	layoutOrder = layoutOrder + 1
	return layoutOrder
end

local function createHeader(text)
	local label = Instance.new("TextLabel")
	label.Name = "Header_" .. text
	label.Size = UDim2.new(1, 0, 0, 28)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 200, 50)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = nextOrder()
	label.ZIndex = 51
	label.Parent = panel
	return label
end

local function createButton(text, callback)
	local btn = Instance.new("TextButton")
	btn.Name = "Btn_" .. text
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	btn.Text = text
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.LayoutOrder = nextOrder()
	btn.ZIndex = 51
	btn.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(callback)

	-- Hover effect
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	end)

	return btn
end

local function createToggleButton(text, callback)
	local btn = createButton(text, function() end)
	local isOn = false
	btn.MouseButton1Click:Connect(function()
		isOn = not isOn
		if isOn then
			btn.BackgroundColor3 = Color3.fromRGB(30, 120, 50)
			btn.Text = text .. " [ON]"
		else
			btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
			btn.Text = text
		end
		callback(isOn)
	end)
	return btn
end

local function createDropdownButton(text, options, callback)
	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. text
	frame.Size = UDim2.new(1, 0, 0, 32)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = nextOrder()
	frame.ZIndex = 51
	frame.Parent = panel

	local innerLayout = Instance.new("UIListLayout")
	innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	innerLayout.Padding = UDim.new(0, 2)
	innerLayout.Parent = frame

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.Name = "Opt_" .. opt
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(60, 45, 70)
		btn.Text = text .. ": " .. opt
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.LayoutOrder = i
		btn.ZIndex = 51
		btn.Parent = frame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			callback(opt)
		end)
		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(60, 45, 70)
		end)
	end

	frame.Size = UDim2.new(1, 0, 0, #options * 30)
	return frame
end

local function createSeparator()
	local sep = Instance.new("Frame")
	sep.Name = "Sep"
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	sep.BorderSizePixel = 0
	sep.LayoutOrder = nextOrder()
	sep.ZIndex = 51
	sep.Parent = panel
end

local function createTextBlock(text)
	local label = Instance.new("TextLabel")
	label.Name = "Info"
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(180, 180, 200)
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.LayoutOrder = nextOrder()
	label.ZIndex = 51
	label.Parent = panel
	return label
end

------------------------------------------------------------
-- BUILD PANEL CONTENTS
------------------------------------------------------------

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "⚙ DEV PANEL"
title.TextColor3 = Color3.fromRGB(255, 100, 100)
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.LayoutOrder = nextOrder()
title.ZIndex = 51
title.Parent = panel

createSeparator()

-- === ENEMY CONTROLS ===
createHeader("ENEMY CONTROLS")

createToggleButton("Freeze Enemies", function(on)
	freezeOn = on
	if DevFreezeEvent then DevFreezeEvent:FireServer() end
end)

createButton("Kill All Enemies", function()
	if DevKillAllEvent then DevKillAllEvent:FireServer() end
end)

createSeparator()
createHeader("SPAWN ENEMY")
createDropdownButton("Spawn", {"Thug", "Brawler", "Speedster"}, function(typeName)
	if DevSpawnEnemyEvent then DevSpawnEnemyEvent:FireServer(typeName) end
end)

createSeparator()
createHeader("ENEMY ACTIONS")

createButton("Trigger Enemy Taunt", function()
	if DevTriggerTauntEvent then DevTriggerTauntEvent:FireServer() end
end)

createButton("Trigger Enemy Combo", function()
	if DevTriggerComboEvent then DevTriggerComboEvent:FireServer() end
end)

createSeparator()

-- === PLAYER ANIMATIONS ===
createHeader("PLAYER ANIMATIONS")

local function playPlayerAnim(animFunc, ...)
	local char = player.Character
	if not char then return end
	if not AnimationManager.HasJoints(char) then
		AnimationManager.SetupJoints(char, 1)
	end
	animFunc(...)
end

createButton("Light 1", function()
	playPlayerAnim(AnimationManager.PlayLightPunch, player.Character, 1)
end)

createButton("Light 2", function()
	playPlayerAnim(AnimationManager.PlayLightPunch, player.Character, 2)
end)

createButton("Light 3", function()
	playPlayerAnim(AnimationManager.PlayLightPunch, player.Character, 3)
end)

createButton("Light 4 (Uppercut)", function()
	playPlayerAnim(AnimationManager.PlayLightPunch, player.Character, 4)
end)

createButton("Heavy Punch", function()
	playPlayerAnim(AnimationManager.PlayHeavyPunch, player.Character)
end)

createButton("Block", function()
	playPlayerAnim(AnimationManager.PlayBlock, player.Character)
	task.delay(1, function()
		if player.Character then
			AnimationManager.PlayUnblock(player.Character)
		end
	end)
end)

createButton("Dodge", function()
	playPlayerAnim(AnimationManager.PlayDodge, player.Character)
end)

createButton("Hit React", function()
	playPlayerAnim(AnimationManager.PlayHitReaction, player.Character, false)
end)

createSeparator()

-- === GAME CONTROLS ===
createHeader("GAME CONTROLS")

createToggleButton("God Mode", function(on)
	godModeOn = on
	if DevGodModeEvent then DevGodModeEvent:FireServer() end
end)

createButton("Spawn Next Wave", function()
	if DevSpawnWaveEvent then DevSpawnWaveEvent:FireServer() end
end)

------------------------------------------------------------
-- TOGGLE LOGIC
------------------------------------------------------------
local function togglePanel()
	panelOpen = not panelOpen
	panel.Visible = panelOpen
	backdrop.Visible = panelOpen

	if panelOpen then
		-- Unlock mouse so buttons are clickable (flag stops camera from re-locking)
		_G.MouseFree = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		-- Re-lock mouse for camera control
		_G.MouseFree = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F9 or input.KeyCode == Enum.KeyCode.Grave then
		togglePanel()
	end
end)

-- Connect backdrop close (now that togglePanel is defined)
backdrop.MouseButton1Click:Connect(function()
	if panelOpen then
		togglePanel()
	end
end)

print("[BrawlAlley] DevPanel loaded (F9 or ` to toggle)")
