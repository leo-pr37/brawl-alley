--[[
	UIController (Client)
	Manages all HUD elements: health bar, score, combo counter,
	wave indicator, start screen, game over screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyTypes = require(Shared:WaitForChild("EnemyTypes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Disable default Roblox UI elements
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Remote events
local GameStateEvent = ReplicatedStorage:WaitForChild("GameStateEvent")
local ScoreEvent = ReplicatedStorage:WaitForChild("ScoreEvent")
local DamageEvent = ReplicatedStorage:WaitForChild("DamageEvent")
local EnemyHitEvent = ReplicatedStorage:WaitForChild("EnemyHitEvent")
local PlayerDiedEvent = ReplicatedStorage:WaitForChild("PlayerDiedEvent")
local RequestRestartEvent = ReplicatedStorage:WaitForChild("RequestRestartEvent")
local RequestGameStartEvent = ReplicatedStorage:WaitForChild("RequestGameStartEvent")
local SpawnEffectEvent = ReplicatedStorage:WaitForChild("SpawnEffectEvent")

------------------------------------------------------------
-- CREATE UI
------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrawlAlleyUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

_G.MouseFree = true
_G.GameState = "Lobby"
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
UserInputService.MouseIconEnabled = true

-- ===== HEALTH BAR =====
local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthFrame"
healthFrame.Size = UDim2.new(0.3, 0, 0, 30)
healthFrame.Position = UDim2.new(0.02, 0, 0.92, 0)
healthFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
healthFrame.BorderSizePixel = 0
healthFrame.Parent = screenGui

local healthCorner = Instance.new("UICorner")
healthCorner.CornerRadius = UDim.new(0, 6)
healthCorner.Parent = healthFrame

local healthBorder = Instance.new("UIStroke")
healthBorder.Color = Color3.fromRGB(200, 200, 200)
healthBorder.Thickness = 2
healthBorder.Parent = healthFrame

local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = Color3.fromRGB(0, 200, 50)
healthFill.BorderSizePixel = 0
healthFill.Parent = healthFrame

local healthFillCorner = Instance.new("UICorner")
healthFillCorner.CornerRadius = UDim.new(0, 6)
healthFillCorner.Parent = healthFill

local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthLabel"
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.Text = "100 / 100"
healthLabel.TextColor3 = Color3.new(1, 1, 1)
healthLabel.Font = Enum.Font.GothamBold
healthLabel.TextSize = 16
healthLabel.ZIndex = 2
healthLabel.Parent = healthFrame

local healthTitle = Instance.new("TextLabel")
healthTitle.Name = "HealthTitle"
healthTitle.Size = UDim2.new(0.3, 0, 0, 20)
healthTitle.Position = UDim2.new(0.02, 0, 0.88, 0)
healthTitle.BackgroundTransparency = 1
healthTitle.Text = "HEALTH"
healthTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
healthTitle.Font = Enum.Font.GothamBold
healthTitle.TextSize = 14
healthTitle.TextXAlignment = Enum.TextXAlignment.Left
healthTitle.Parent = screenGui

-- ===== SCORE =====
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Name = "ScoreLabel"
scoreLabel.Size = UDim2.new(0, 200, 0, 40)
scoreLabel.Position = UDim2.new(0.5, -100, 0.02, 0)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Text = "SCORE: 0"
scoreLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextSize = 28
scoreLabel.TextStrokeTransparency = 0.5
scoreLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
scoreLabel.Parent = screenGui

-- ===== COMBO COUNTER =====
local comboFrame = Instance.new("Frame")
comboFrame.Name = "ComboFrame"
comboFrame.Size = UDim2.new(0, 200, 0, 60)
comboFrame.Position = UDim2.new(0.75, 0, 0.4, 0)
comboFrame.BackgroundTransparency = 1
comboFrame.Parent = screenGui

local comboLabel = Instance.new("TextLabel")
comboLabel.Name = "ComboLabel"
comboLabel.Size = UDim2.new(1, 0, 0.6, 0)
comboLabel.BackgroundTransparency = 1
comboLabel.Text = ""
comboLabel.TextColor3 = Color3.fromRGB(255, 100, 50)
comboLabel.Font = Enum.Font.GothamBlack
comboLabel.TextSize = 36
comboLabel.TextStrokeTransparency = 0.3
comboLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
comboLabel.Parent = comboFrame

local comboSubLabel = Instance.new("TextLabel")
comboSubLabel.Name = "ComboSub"
comboSubLabel.Size = UDim2.new(1, 0, 0.4, 0)
comboSubLabel.Position = UDim2.new(0, 0, 0.6, 0)
comboSubLabel.BackgroundTransparency = 1
comboSubLabel.Text = ""
comboSubLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
comboSubLabel.Font = Enum.Font.GothamBold
comboSubLabel.TextSize = 18
comboSubLabel.TextStrokeTransparency = 0.5
comboSubLabel.Parent = comboFrame

-- ===== WAVE INDICATOR =====
local waveLabel = Instance.new("TextLabel")
waveLabel.Name = "WaveLabel"
waveLabel.Size = UDim2.new(0.5, 0, 0, 50)
waveLabel.Position = UDim2.new(0.25, 0, 0.15, 0)
waveLabel.BackgroundTransparency = 1
waveLabel.Text = ""
waveLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
waveLabel.Font = Enum.Font.GothamBlack
waveLabel.TextSize = 42
waveLabel.TextStrokeTransparency = 0.2
waveLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
waveLabel.TextTransparency = 1
waveLabel.Parent = screenGui

-- ===== DAMAGE FLASH (red border + subtle tint) =====
local damageFlash = Instance.new("Frame")
damageFlash.Name = "DamageFlash"
damageFlash.Size = UDim2.new(1, 0, 1, 0)
damageFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
damageFlash.BackgroundTransparency = 1
damageFlash.BorderSizePixel = 0
damageFlash.ZIndex = 10
damageFlash.Parent = screenGui

local damageBorder = Instance.new("UIStroke")
damageBorder.Name = "DamageBorder"
damageBorder.Color = Color3.fromRGB(200, 0, 0)
damageBorder.Thickness = 8
damageBorder.Transparency = 1
damageBorder.Parent = damageFlash

-- ===== START SCREEN =====
local startScreen = Instance.new("Frame")
startScreen.Name = "StartScreen"
startScreen.Size = UDim2.new(1, 0, 1, 0)
startScreen.BackgroundColor3 = Color3.fromRGB(10, 5, 15)
startScreen.BackgroundTransparency = 0
startScreen.BorderSizePixel = 0
startScreen.ZIndex = 20
startScreen.Parent = screenGui

local backgroundOverlay = Instance.new("Frame")
backgroundOverlay.Name = "BackgroundOverlay"
backgroundOverlay.Size = UDim2.new(1, 0, 1, 0)
backgroundOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backgroundOverlay.BackgroundTransparency = 0.35
backgroundOverlay.BorderSizePixel = 0
backgroundOverlay.ZIndex = 20
backgroundOverlay.Parent = startScreen

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(0.8, 0, 0.2, 0)
titleLabel.Position = UDim2.new(0.1, 0, 0.15, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "BRAWL ALLEY"
titleLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 72
titleLabel.TextStrokeTransparency = 0
titleLabel.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
titleLabel.ZIndex = 21
titleLabel.Parent = startScreen

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(0.6, 0, 0.1, 0)
subtitleLabel.Position = UDim2.new(0.2, 0, 0.35, 0)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Streets of Fury"
subtitleLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
subtitleLabel.Font = Enum.Font.GothamBold
subtitleLabel.TextSize = 32
subtitleLabel.TextStrokeTransparency = 0.3
subtitleLabel.ZIndex = 21
subtitleLabel.Parent = startScreen

local artOfWarQuotes = {
	"Victorious warriors win first and then go to war.",
	"The supreme art of war is to subdue the enemy without fighting.",
	"In the midst of chaos, there is also opportunity.",
	"If you know the enemy and know yourself, you need not fear the result of a hundred battles.",
	"Pretend inferiority and encourage arrogance.",
	"Treat your men as you would your own beloved sons, and they will follow you into the deepest valley.",
	"He who is prudent and lies in wait for an enemy who is not, will be victorious.",
	"Opportunities multiply as they are seized.",
	"Move swift as the wind and closely formed as the forest.",
	"To know your enemy, you must become your enemy.",
}

local quoteLabel = Instance.new("TextLabel")
quoteLabel.Name = "Quote"
quoteLabel.Size = UDim2.new(0.6, 0, 0.18, 0)
quoteLabel.Position = UDim2.new(0.2, 0, 0.46, 0)
quoteLabel.BackgroundTransparency = 1
quoteLabel.Text = "\"" .. artOfWarQuotes[math.random(1, #artOfWarQuotes)] .. "\"\n- Sun Tzu"
quoteLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
quoteLabel.Font = Enum.Font.Gotham
quoteLabel.TextSize = 20
quoteLabel.TextWrapped = true
quoteLabel.TextStrokeTransparency = 0.5
quoteLabel.ZIndex = 21
quoteLabel.Parent = startScreen

local controlsToggleButton = Instance.new("TextButton")
controlsToggleButton.Name = "ControlsToggle"
controlsToggleButton.Size = UDim2.new(0.2, 0, 0.05, 0)
controlsToggleButton.Position = UDim2.new(0.4, 0, 0.63, 0)
controlsToggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
controlsToggleButton.Text = "SHOW CONTROLS"
controlsToggleButton.TextColor3 = Color3.new(1, 1, 1)
controlsToggleButton.Font = Enum.Font.GothamBold
controlsToggleButton.TextSize = 14
controlsToggleButton.ZIndex = 21
controlsToggleButton.Parent = startScreen
local controlsToggleCorner = Instance.new("UICorner")
controlsToggleCorner.CornerRadius = UDim.new(0, 8)
controlsToggleCorner.Parent = controlsToggleButton

local controlsPanel = Instance.new("Frame")
controlsPanel.Name = "ControlsPanel"
controlsPanel.Size = UDim2.new(0.6, 0, 0.2, 0)
controlsPanel.Position = UDim2.new(0.2, 0, 0.46, 0)
controlsPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
controlsPanel.BackgroundTransparency = 0.35
controlsPanel.Visible = false
controlsPanel.ZIndex = 21
controlsPanel.Parent = startScreen
local controlsPanelCorner = Instance.new("UICorner")
controlsPanelCorner.CornerRadius = UDim.new(0, 8)
controlsPanelCorner.Parent = controlsPanel

local controlsLabel = Instance.new("TextLabel")
controlsLabel.Name = "Controls"
controlsLabel.Size = UDim2.new(1, -20, 1, -20)
controlsLabel.Position = UDim2.new(0, 10, 0, 10)
controlsLabel.BackgroundTransparency = 1
controlsLabel.Text = [[CONTROLS:
WASD - Move
Left Click - Light Attack
Hold Left Click - Heavy Attack
Left Click (holding item) - Use Item
Right Click - Block
Shift / Q - Dodge
Ctrl (hold) - Sprint
E - Pick Up Item
F - Throw Held Item
R - Drop Held Item]]
controlsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
controlsLabel.Font = Enum.Font.Gotham
controlsLabel.TextSize = 16
controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
controlsLabel.TextWrapped = true
controlsLabel.TextStrokeTransparency = 0.5
controlsLabel.ZIndex = 22
controlsLabel.Parent = controlsPanel

controlsToggleButton.MouseButton1Click:Connect(function()
	controlsPanel.Visible = not controlsPanel.Visible
	controlsToggleButton.Text = controlsPanel.Visible and "HIDE CONTROLS" or "SHOW CONTROLS"
end)

local levelKeys = EnemyTypes.LevelOrder or {EnemyTypes.DefaultLevel or "Alley"}
if #levelKeys == 0 then
	table.insert(levelKeys, EnemyTypes.DefaultLevel or "Alley")
end
local difficultyOptions = {"Easy", "Normal", "Hard"}

local function getLevelDisplayName(levelKey)
	local level = EnemyTypes.GetLevel(levelKey)
	return level and level.DisplayName or levelKey
end

local function createSelector(parent, titleText, yScale, options, formatter)
	local container = Instance.new("Frame")
	container.Name = titleText .. "Selector"
	container.Size = UDim2.new(0.52, 0, 0.08, 0)
	container.Position = UDim2.new(0.24, 0, yScale, 0)
	container.BackgroundTransparency = 1
	container.ZIndex = 21
	container.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.3, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Text = titleText .. ":"
	title.TextColor3 = Color3.fromRGB(220, 220, 220)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 21
	title.Parent = container

	local left = Instance.new("TextButton")
	left.Size = UDim2.new(0, 36, 0, 36)
	left.Position = UDim2.new(0.34, 0, 0.5, -18)
	left.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	left.Text = "<"
	left.TextColor3 = Color3.new(1, 1, 1)
	left.Font = Enum.Font.GothamBlack
	left.TextSize = 24
	left.ZIndex = 21
	left.Parent = container
	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = left

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0.42, 0, 1, 0)
	valueLabel.Position = UDim2.new(0.46, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 18
	valueLabel.ZIndex = 21
	valueLabel.Parent = container

	local right = Instance.new("TextButton")
	right.Size = UDim2.new(0, 36, 0, 36)
	right.Position = UDim2.new(0.9, 0, 0.5, -18)
	right.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	right.Text = ">"
	right.TextColor3 = Color3.new(1, 1, 1)
	right.Font = Enum.Font.GothamBlack
	right.TextSize = 24
	right.ZIndex = 21
	right.Parent = container
	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 8)
	rightCorner.Parent = right

	local idx = 1
	local function updateLabel()
		local value = options[idx]
		if formatter then
			value = formatter(value)
		end
		valueLabel.Text = value
	end

	left.MouseButton1Click:Connect(function()
		idx = idx - 1
		if idx < 1 then idx = #options end
		updateLabel()
	end)

	right.MouseButton1Click:Connect(function()
		idx = idx + 1
		if idx > #options then idx = 1 end
		updateLabel()
	end)

	local selector = {}
	function selector.GetValue()
		return options[idx]
	end

	function selector.SetValue(value)
		for i, option in ipairs(options) do
			if option == value then
				idx = i
				break
			end
		end
		updateLabel()
	end

	updateLabel()
	return selector
end

local levelSelector = createSelector(startScreen, "LEVEL", 0.7, levelKeys, getLevelDisplayName)
local difficultySelector = createSelector(startScreen, "DIFFICULTY", 0.78, difficultyOptions)

local startGameButton = Instance.new("TextButton")
startGameButton.Name = "StartGameButton"
startGameButton.Size = UDim2.new(0.3, 0, 0.08, 0)
startGameButton.Position = UDim2.new(0.35, 0, 0.86, 0)
startGameButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
startGameButton.Text = "START BRAWL"
startGameButton.TextColor3 = Color3.new(1, 1, 1)
startGameButton.Font = Enum.Font.GothamBlack
startGameButton.TextSize = 24
startGameButton.ZIndex = 21
startGameButton.Parent = startScreen
local startButtonCorner = Instance.new("UICorner")
startButtonCorner.CornerRadius = UDim.new(0, 10)
startButtonCorner.Parent = startGameButton

local waitingLabel = Instance.new("TextLabel")
waitingLabel.Name = "Waiting"
waitingLabel.Size = UDim2.new(0.7, 0, 0.05, 0)
waitingLabel.Position = UDim2.new(0.15, 0, 0.94, 0)
waitingLabel.BackgroundTransparency = 1
waitingLabel.Text = "Waiting for start..."
waitingLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
waitingLabel.Font = Enum.Font.GothamBold
waitingLabel.TextSize = 18
waitingLabel.ZIndex = 21
waitingLabel.Parent = startScreen

startGameButton.MouseButton1Click:Connect(function()
	local selectedLevel = levelSelector.GetValue()
	local selectedDifficulty = difficultySelector.GetValue()
	waitingLabel.Text = "Starting " .. getLevelDisplayName(selectedLevel) .. " (" .. selectedDifficulty .. ")..."
	startGameButton.Text = "STARTING..."
	startGameButton.AutoButtonColor = false
	startGameButton.Active = false
	RequestGameStartEvent:FireServer(selectedLevel, selectedDifficulty)
end)

-- Pulse animation for waiting text
task.spawn(function()
	while waitingLabel and waitingLabel.Parent do
		for i = 0, 1, 0.02 do
			if not waitingLabel or not waitingLabel.Parent then break end
			waitingLabel.TextTransparency = 0.3 + 0.5 * math.sin(i * math.pi * 2)
			task.wait(0.03)
		end
	end
end)

-- ===== GAME OVER SCREEN =====
local gameOverScreen = Instance.new("Frame")
gameOverScreen.Name = "GameOverScreen"
gameOverScreen.Size = UDim2.new(1, 0, 1, 0)
gameOverScreen.BackgroundColor3 = Color3.fromRGB(10, 5, 5)
gameOverScreen.BackgroundTransparency = 1
gameOverScreen.BorderSizePixel = 0
gameOverScreen.Visible = false
gameOverScreen.ZIndex = 20
gameOverScreen.Parent = screenGui

local gameOverLabel = Instance.new("TextLabel")
gameOverLabel.Name = "GameOverText"
gameOverLabel.Size = UDim2.new(0.8, 0, 0.2, 0)
gameOverLabel.Position = UDim2.new(0.1, 0, 0.2, 0)
gameOverLabel.BackgroundTransparency = 1
gameOverLabel.Text = "GAME OVER"
gameOverLabel.TextColor3 = Color3.fromRGB(255, 30, 30)
gameOverLabel.Font = Enum.Font.GothamBlack
gameOverLabel.TextSize = 64
gameOverLabel.TextStrokeTransparency = 0
gameOverLabel.ZIndex = 21
gameOverLabel.Parent = gameOverScreen

local finalScoreLabel = Instance.new("TextLabel")
finalScoreLabel.Name = "FinalScore"
finalScoreLabel.Size = UDim2.new(0.6, 0, 0.1, 0)
finalScoreLabel.Position = UDim2.new(0.2, 0, 0.45, 0)
finalScoreLabel.BackgroundTransparency = 1
finalScoreLabel.Text = "FINAL SCORE: 0"
finalScoreLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
finalScoreLabel.Font = Enum.Font.GothamBold
finalScoreLabel.TextSize = 36
finalScoreLabel.TextStrokeTransparency = 0.3
finalScoreLabel.ZIndex = 21
finalScoreLabel.Parent = gameOverScreen

local restartButton = Instance.new("TextButton")
restartButton.Name = "RestartButton"
restartButton.Size = UDim2.new(0, 250, 0, 60)
restartButton.Position = UDim2.new(0.5, -125, 0.65, 0)
restartButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
restartButton.Text = "PLAY AGAIN"
restartButton.TextColor3 = Color3.new(1, 1, 1)
restartButton.Font = Enum.Font.GothamBlack
restartButton.TextSize = 28
restartButton.ZIndex = 21
restartButton.Parent = gameOverScreen

local restartCorner = Instance.new("UICorner")
restartCorner.CornerRadius = UDim.new(0, 10)
restartCorner.Parent = restartButton

restartButton.MouseButton1Click:Connect(function()
	RequestRestartEvent:FireServer()
end)

------------------------------------------------------------
-- STATE TRACKING
------------------------------------------------------------
local currentScore = 0
local currentWave = 0

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------

-- Game state changes
GameStateEvent.OnClientEvent:Connect(function(state, data)
	if state == "GameStart" then
		_G.GameState = "Playing"
		if typeof(data) == "table" then
			if data.level then
				levelSelector.SetValue(data.level)
			end
			if data.difficulty then
				difficultySelector.SetValue(data.difficulty)
			end
			local levelName = data.levelName or getLevelDisplayName(levelSelector.GetValue())
			local difficultyName = data.difficulty or difficultySelector.GetValue()
			waitingLabel.Text = "Starting " .. levelName .. " (" .. difficultyName .. ")..."
		end

		-- Hide start screen
		TweenService:Create(startScreen, TweenInfo.new(1), {BackgroundTransparency = 1}):Play()
		TweenService:Create(backgroundOverlay, TweenInfo.new(1), {BackgroundTransparency = 1}):Play()
		task.wait(1)
		startScreen.Visible = false
		startGameButton.Text = "START BRAWL"
		startGameButton.AutoButtonColor = true
		startGameButton.Active = true
		waitingLabel.Text = "Waiting for start..."
		backgroundOverlay.BackgroundTransparency = 0.35

		-- Hide game over screen
		gameOverScreen.Visible = false
		gameOverScreen.BackgroundTransparency = 1

		-- Re-lock mouse for gameplay
		_G.MouseFree = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		-- Reset UI
		currentScore = 0
		scoreLabel.Text = "SCORE: 0"
		comboLabel.Text = ""
		comboSubLabel.Text = ""

	elseif state == "WaveStart" then
		currentWave = data
		-- Show wave announcement
		waveLabel.Text = "WAVE " .. tostring(currentWave)
		waveLabel.TextTransparency = 0
		waveLabel.TextStrokeTransparency = 0

		-- Animate: fade in, hold, fade out
		task.spawn(function()
			-- Scale pop effect
			waveLabel.TextSize = 60
			TweenService:Create(waveLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {TextSize = 42}):Play()
			task.wait(2)
			TweenService:Create(waveLabel, TweenInfo.new(0.5), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		end)

	elseif state == "GameOver" then
		_G.GameState = "GameOver"
		local finalScore = data or currentScore
		finalScoreLabel.Text = "FINAL SCORE: " .. tostring(finalScore)
		gameOverScreen.Visible = true
		gameOverScreen.BackgroundTransparency = 0.3
		TweenService:Create(gameOverScreen, TweenInfo.new(1), {BackgroundTransparency = 0.3}):Play()

		-- Unlock mouse so player can click Play Again
		_G.MouseFree = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

-- Score updates
ScoreEvent.OnClientEvent:Connect(function(scoreType, amount, total)
	currentScore = total
	scoreLabel.Text = "SCORE: " .. tostring(total)

	-- Pop effect on score change
	task.spawn(function()
		scoreLabel.TextSize = 34
		TweenService:Create(scoreLabel, TweenInfo.new(0.2, Enum.EasingStyle.Back), {TextSize = 28}):Play()
	end)
end)

-- Damage taken — red border flash + subtle tint
DamageEvent.OnClientEvent:Connect(function(damage, wasBlocked, sourcePos)
	task.spawn(function()
		if wasBlocked then
			damageFlash.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
			damageBorder.Color = Color3.fromRGB(0, 120, 200)
		else
			damageFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			damageBorder.Color = Color3.fromRGB(200, 0, 0)
		end
		damageFlash.BackgroundTransparency = 0.85
		damageBorder.Transparency = 0
		TweenService:Create(damageFlash, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		TweenService:Create(damageBorder, TweenInfo.new(0.5), {Transparency = 1}):Play()
	end)
end)

-- Combo updates (from local BindableEvent)
task.spawn(function()
	local comboEvent = ReplicatedStorage:WaitForChild("ComboUpdate", 10)
	if not comboEvent then
		comboEvent = Instance.new("BindableEvent")
		comboEvent.Name = "ComboUpdate"
		comboEvent.Parent = ReplicatedStorage
	end

	comboEvent.Event:Connect(function(count, attackType)
		if count <= 0 then
			comboLabel.Text = ""
			comboSubLabel.Text = ""
		else
			comboLabel.Text = tostring(count) .. "x COMBO"
			if count >= 4 then
				comboSubLabel.Text = "FINISHER!"
				comboLabel.TextColor3 = Color3.fromRGB(255, 50, 255)
			elseif count >= 3 then
				comboSubLabel.Text = "GREAT!"
				comboLabel.TextColor3 = Color3.fromRGB(255, 150, 50)
			else
				comboSubLabel.Text = attackType == "HeavyAttack" and "HEAVY!" or "HIT!"
				comboLabel.TextColor3 = Color3.fromRGB(255, 100, 50)
			end

			-- Scale pop
			comboLabel.TextSize = 48
			TweenService:Create(comboLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back), {TextSize = 36}):Play()
		end
	end)
end)

-- Enemy hit effects
EnemyHitEvent.OnClientEvent:Connect(function(enemy, hitType, sourcePos, attackType)
	if not enemy or not enemy:IsA("Model") or not enemy.PrimaryPart then return end

	if hitType == "hit" then
		-- Flash enemy white briefly
		task.spawn(function()
			local parts = {}
			for _, part in ipairs(enemy:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(parts, {part = part, color = part.BrickColor})
					part.BrickColor = BrickColor.new("White")
				end
			end
			task.wait(0.1)
			for _, info in ipairs(parts) do
				if info.part and info.part.Parent then
					info.part.BrickColor = info.color
				end
			end
		end)

		-- Hit particle effect
		task.spawn(function()
			local hitPart = Instance.new("Part")
			hitPart.Size = Vector3.new(0.5, 0.5, 0.5)
			hitPart.Position = enemy.PrimaryPart.Position
			hitPart.Anchored = true
			hitPart.CanCollide = false
			hitPart.BrickColor = BrickColor.new("Bright yellow")
			hitPart.Material = Enum.Material.Neon
			hitPart.Shape = Enum.PartType.Ball
			hitPart.Parent = workspace

			TweenService:Create(hitPart, TweenInfo.new(0.3), {
				Size = Vector3.new(3, 3, 3),
				Transparency = 1
			}):Play()

			task.wait(0.3)
			hitPart:Destroy()
		end)

	elseif hitType == "attack" then
		-- Enemy attack indicator: red flash
		task.spawn(function()
			local parts = {}
			for _, part in ipairs(enemy:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(parts, {part = part, color = part.BrickColor})
					part.BrickColor = BrickColor.new("Really red")
				end
			end
			task.wait(0.15)
			for _, info in ipairs(parts) do
				if info.part and info.part.Parent then
					info.part.BrickColor = info.color
				end
			end
		end)
	end
end)

-- Spawn effect
SpawnEffectEvent.OnClientEvent:Connect(function(position)
	task.spawn(function()
		local ring = Instance.new("Part")
		ring.Size = Vector3.new(1, 0.2, 1)
		ring.Position = position
		ring.Anchored = true
		ring.CanCollide = false
		ring.BrickColor = BrickColor.new("Really red")
		ring.Material = Enum.Material.Neon
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Parent = workspace

		TweenService:Create(ring, TweenInfo.new(0.5), {
			Size = Vector3.new(1, 8, 8),
			Transparency = 1
		}):Play()

		task.wait(0.5)
		ring:Destroy()
	end)
end)

-- Player died
PlayerDiedEvent.OnClientEvent:Connect(function()
	-- Show "YOU DIED" text briefly
	task.spawn(function()
		local diedLabel = Instance.new("TextLabel")
		diedLabel.Size = UDim2.new(0.5, 0, 0.15, 0)
		diedLabel.Position = UDim2.new(0.25, 0, 0.35, 0)
		diedLabel.BackgroundTransparency = 1
		diedLabel.Text = "YOU DIED"
		diedLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
		diedLabel.Font = Enum.Font.GothamBlack
		diedLabel.TextSize = 56
		diedLabel.TextStrokeTransparency = 0
		diedLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		diedLabel.ZIndex = 15
		diedLabel.Parent = screenGui

		task.wait(3)
		TweenService:Create(diedLabel, TweenInfo.new(1), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		task.wait(1)
		diedLabel:Destroy()
	end)
end)

------------------------------------------------------------
-- HEALTH BAR UPDATE LOOP
------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)

	-- Color: green -> yellow -> red
	if healthPercent > 0.5 then
		local t = (healthPercent - 0.5) * 2
		healthFill.BackgroundColor3 = Color3.fromRGB(
			math.floor(255 * (1 - t)),
			math.floor(200 * t + 50),
			50
		)
	else
		local t = healthPercent * 2
		healthFill.BackgroundColor3 = Color3.fromRGB(
			255,
			math.floor(200 * t),
			math.floor(50 * t)
		)
	end

	healthLabel.Text = math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)
end)

print("[BrawlAlley] UIController loaded")
