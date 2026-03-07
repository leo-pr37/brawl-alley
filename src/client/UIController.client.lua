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
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyTypes = require(Shared:WaitForChild("EnemyTypes"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Disable default Roblox UI elements
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Remote events
local Remotes = Shared:WaitForChild("Remotes", 10)
if not Remotes then
	error("[UIController] Shared.Remotes not found")
end

local function getRemote(name)
	local remote = Remotes:FindFirstChild(name) or Remotes:WaitForChild(name, 10)
	if not remote then
		remote = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 2)
	end
	if not remote then
		error(("[UIController] Remote not found: %s"):format(name))
	end
	return remote
end

local GameStateEvent = getRemote("GameStateEvent")
local ScoreEvent = getRemote("ScoreEvent")
local DamageEvent = getRemote("DamageEvent")
local EnemyHitEvent = getRemote("EnemyHitEvent")
local PlayerDiedEvent = getRemote("PlayerDiedEvent")
local RequestRestartEvent = getRemote("RequestRestartEvent")
local RequestGameStartEvent = getRemote("RequestGameStartEvent")
local SpawnEffectEvent = getRemote("SpawnEffectEvent")
local TeamStatusEvent = getRemote("TeamStatusEvent")
local MoneyEvent = getRemote("MoneyEvent")
local ShopPurchaseEvent = getRemote("ShopPurchase")
local ShopResultEvent = getRemote("ShopResult")

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

local audioConfig = CombatConfig.Audio or {}
local musicConfig = audioConfig.Music or {}

local function createMusic(name, soundId, volume)
	if not soundId or soundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = volume or 0.2
	sound.Parent = SoundService
	return sound
end

local lobbyMusic = createMusic("LobbyMusic", musicConfig.LobbyTrackId, musicConfig.Volume)
local battleMusic = createMusic("BattleMusic", musicConfig.BattleTrackId, musicConfig.Volume)

local musicToPreload = {}
for _, music in ipairs({lobbyMusic, battleMusic}) do
	if music then
		table.insert(musicToPreload, music)
	end
end
if #musicToPreload > 0 then
	task.spawn(function()
		ContentProvider:PreloadAsync(musicToPreload)
	end)
end

local function setMusicState(stateName)
	local inBattle = (stateName == "Playing")
	if lobbyMusic then
		if inBattle then
			lobbyMusic:Stop()
		elseif not lobbyMusic.IsPlaying then
			lobbyMusic:Play()
		end
	end
	if battleMusic then
		if inBattle then
			if not battleMusic.IsPlaying then
				battleMusic:Play()
			end
		else
			battleMusic:Stop()
		end
	end
end

setMusicState("Lobby")

-- ===== HEALTH BAR =====
local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthFrame"
healthFrame.Size = UDim2.new(0.3, 0, 0, 30)
healthFrame.Position = UDim2.new(0.02, 0, 0.92, 0)
healthFrame.AnchorPoint = Vector2.new(0, 1)
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
healthTitle.AnchorPoint = Vector2.new(0, 1)
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

-- ===== MONEY =====
local moneyLabel = Instance.new("TextLabel")
moneyLabel.Name = "MoneyLabel"
moneyLabel.Size = UDim2.new(0, 220, 0, 32)
moneyLabel.Position = UDim2.new(0.02, 0, 0.84, 0)
moneyLabel.AnchorPoint = Vector2.new(0, 1)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Text = "$0"
moneyLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
moneyLabel.Font = Enum.Font.GothamBold
moneyLabel.TextSize = 26
moneyLabel.TextStrokeTransparency = 0.45
moneyLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.Parent = screenGui

local shopPromptLabel = Instance.new("TextLabel")
shopPromptLabel.Name = "ShopPromptLabel"
shopPromptLabel.Size = UDim2.new(0, 260, 0, 18)
shopPromptLabel.Position = UDim2.new(0.02, 0, 0.87, 0)
shopPromptLabel.AnchorPoint = Vector2.new(0, 1)
shopPromptLabel.BackgroundTransparency = 1
shopPromptLabel.Text = "Press B to open Shop"
shopPromptLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
shopPromptLabel.Font = Enum.Font.Gotham
shopPromptLabel.TextSize = 13
shopPromptLabel.TextXAlignment = Enum.TextXAlignment.Left
shopPromptLabel.Parent = screenGui

-- ===== STAMINA BAR =====
local staminaFrame = Instance.new("Frame")
staminaFrame.Name = "StaminaFrame"
staminaFrame.Size = UDim2.new(0.3, 0, 0, 20)
staminaFrame.Position = UDim2.new(0.02, 0, 0.96, 0)
staminaFrame.AnchorPoint = Vector2.new(0, 1)
staminaFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
staminaFrame.BorderSizePixel = 0
staminaFrame.Parent = screenGui

local staminaCorner = Instance.new("UICorner")
staminaCorner.CornerRadius = UDim.new(0, 6)
staminaCorner.Parent = staminaFrame

local staminaBorder = Instance.new("UIStroke")
staminaBorder.Color = Color3.fromRGB(180, 220, 255)
staminaBorder.Thickness = 2
staminaBorder.Parent = staminaFrame

local staminaFill = Instance.new("Frame")
staminaFill.Name = "StaminaFill"
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(70, 170, 255)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaFrame

local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = UDim.new(0, 6)
staminaFillCorner.Parent = staminaFill

local staminaLabel = Instance.new("TextLabel")
staminaLabel.Name = "StaminaLabel"
staminaLabel.Size = UDim2.new(1, 0, 1, 0)
staminaLabel.BackgroundTransparency = 1
staminaLabel.Text = "100 / 100"
staminaLabel.TextColor3 = Color3.new(1, 1, 1)
staminaLabel.Font = Enum.Font.GothamBold
staminaLabel.TextSize = 14
staminaLabel.ZIndex = 2
staminaLabel.Parent = staminaFrame

local staminaTitle = Instance.new("TextLabel")
staminaTitle.Name = "StaminaTitle"
staminaTitle.Size = UDim2.new(0.3, 0, 0, 16)
staminaTitle.Position = UDim2.new(0.02, 0, 0.94, -18)
staminaTitle.AnchorPoint = Vector2.new(0, 1)
staminaTitle.BackgroundTransparency = 1
staminaTitle.Text = "STAMINA"
staminaTitle.TextColor3 = Color3.fromRGB(180, 220, 255)
staminaTitle.Font = Enum.Font.GothamBold
staminaTitle.TextSize = 12
staminaTitle.TextXAlignment = Enum.TextXAlignment.Left
staminaTitle.Parent = screenGui

local shopToggleTouchButton = Instance.new("TextButton")
shopToggleTouchButton.Name = "ShopToggleTouchButton"
shopToggleTouchButton.Size = UDim2.new(0, 86, 0, 36)
shopToggleTouchButton.Position = UDim2.new(1, -98, 1, -148)
shopToggleTouchButton.AnchorPoint = Vector2.new(0, 1)
shopToggleTouchButton.BackgroundColor3 = Color3.fromRGB(42, 42, 58)
shopToggleTouchButton.TextColor3 = Color3.new(1, 1, 1)
shopToggleTouchButton.Font = Enum.Font.GothamBold
shopToggleTouchButton.TextSize = 15
shopToggleTouchButton.Text = "SHOP"
shopToggleTouchButton.BorderSizePixel = 0
shopToggleTouchButton.ZIndex = 13
shopToggleTouchButton.Visible = false
shopToggleTouchButton.AutoButtonColor = true
shopToggleTouchButton.Parent = screenGui

local shopTouchCorner = Instance.new("UICorner")
shopTouchCorner.CornerRadius = UDim.new(0, 8)
shopTouchCorner.Parent = shopToggleTouchButton

local inventoryFrame = Instance.new("Frame")
inventoryFrame.Name = "InventoryFrame"
inventoryFrame.Size = UDim2.new(0, 240, 0, 54)
inventoryFrame.Position = UDim2.new(0.5, 0, 1, -18)
inventoryFrame.AnchorPoint = Vector2.new(0.5, 1)
inventoryFrame.BackgroundTransparency = 1
inventoryFrame.Parent = screenGui

local crosshairFrame = Instance.new("Frame")
crosshairFrame.Name = "Crosshair"
crosshairFrame.Size = UDim2.new(0, 18, 0, 18)
crosshairFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshairFrame.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairFrame.BackgroundTransparency = 1
crosshairFrame.Visible = false
crosshairFrame.ZIndex = 30
crosshairFrame.Parent = screenGui

local function makeCrosshairBar(size, position)
	local bar = Instance.new("Frame")
	bar.Size = size
	bar.Position = position
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.BackgroundColor3 = Color3.fromRGB(255, 244, 210)
	bar.BorderSizePixel = 0
	bar.ZIndex = 30
	bar.Parent = crosshairFrame
	return bar
end

makeCrosshairBar(UDim2.fromOffset(2, 18), UDim2.new(0.5, 0, 0.5, 0))
makeCrosshairBar(UDim2.fromOffset(18, 2), UDim2.new(0.5, 0, 0.5, 0))

local inventorySlotsUi = {}
for i = 1, 3 do
	local slot = Instance.new("Frame")
	slot.Name = "Slot" .. i
	slot.Size = UDim2.new(0, 68, 0, 54)
	slot.Position = UDim2.new(0, (i - 1) * 78, 0, 0)
	slot.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	slot.BorderSizePixel = 0
	slot.Parent = inventoryFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 120)
	stroke.Thickness = 2
	stroke.Parent = slot

	local key = Instance.new("TextLabel")
	key.Size = UDim2.new(1, -8, 0, 14)
	key.Position = UDim2.new(0, 4, 0, 3)
	key.BackgroundTransparency = 1
	key.Text = tostring(i)
	key.TextColor3 = Color3.fromRGB(180, 180, 190)
	key.Font = Enum.Font.GothamBold
	key.TextSize = 11
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "ItemLabel"
	label.Size = UDim2.new(1, -8, 1, -20)
	label.Position = UDim2.new(0, 4, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = "-"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextWrapped = true
	label.Parent = slot

	inventorySlotsUi[i] = {
		frame = slot,
		stroke = stroke,
		label = label,
	}
end

local function updateInventoryBar(state)
	state = state or {}
	local slots = state.slots or {}
	local activeSlot = state.equippedSlot or 1
	local equipped = state.equipped
	for i = 1, 3 do
		local slotUi = inventorySlotsUi[i]
		local itemName = slots[i]
		slotUi.label.Text = itemName and string.upper(itemName) or "-"
		slotUi.frame.BackgroundColor3 = (i == activeSlot) and Color3.fromRGB(58, 66, 84) or Color3.fromRGB(30, 30, 38)
		slotUi.stroke.Color = (i == activeSlot) and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(100, 100, 120)
	end
	crosshairFrame.Visible = (_G.GameState == "Playing" and equipped == "Pistol")
end

updateInventoryBar({slots = {}, equippedSlot = 1})

local function updateBottomLeftHudLayout()
	local cam = workspace.CurrentCamera
	local viewport = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local shortSide = math.min(viewport.X, viewport.Y)
	local compact = shortSide < 700

	local leftPad = 12
	local bottomPad = compact and 8 or 12
	local barGap = compact and 6 or 10
	local titleGap = compact and 2 or 4
	local healthHeight = compact and 24 or 30
	local staminaHeight = compact and 16 or 20
	local barWidth = math.clamp(math.floor(viewport.X * (compact and 0.4 or 0.32)), 200, compact and 290 or 420)

	healthFrame.Size = UDim2.fromOffset(barWidth, healthHeight)
	staminaFrame.Size = UDim2.fromOffset(barWidth, staminaHeight)

	staminaFrame.Position = UDim2.new(0, leftPad, 1, -bottomPad)
	staminaTitle.Position = UDim2.new(0, leftPad, 1, -(bottomPad + staminaHeight + titleGap))

	healthFrame.Position = UDim2.new(0, leftPad, 1, -(bottomPad + staminaHeight + barGap + healthHeight))
	healthTitle.Position = UDim2.new(0, leftPad, 1, -(bottomPad + staminaHeight + barGap + healthHeight + titleGap))

	moneyLabel.Position = UDim2.new(0, leftPad, 1, -(bottomPad + staminaHeight + barGap + healthHeight + titleGap + 20))
	shopPromptLabel.Position = UDim2.new(0, leftPad, 1, -(bottomPad + staminaHeight + barGap + healthHeight + titleGap + 36))
end

task.defer(updateBottomLeftHudLayout)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(updateBottomLeftHudLayout)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateBottomLeftHudLayout)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateBottomLeftHudLayout)
end

task.spawn(function()
	local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate", 10)
	if inventoryEvent then
		inventoryEvent.Event:Connect(updateInventoryBar)
	end
end)

-- ===== SHOP PANEL =====
local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.Size = UDim2.new(0, 260, 0, 230)
shopPanel.Position = UDim2.new(0.98, -270, 0.98, -240)
shopPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
shopPanel.BackgroundTransparency = 0.2
shopPanel.BorderSizePixel = 0
shopPanel.ZIndex = 12
shopPanel.Visible = false
shopPanel.Parent = screenGui

local shopPanelCorner = Instance.new("UICorner")
shopPanelCorner.CornerRadius = UDim.new(0, 8)
shopPanelCorner.Parent = shopPanel

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, -16, 0, 26)
shopTitle.Position = UDim2.new(0, 8, 0, 6)
shopTitle.BackgroundTransparency = 1
shopTitle.Text = "SHOP (B)"
shopTitle.TextColor3 = Color3.fromRGB(255, 220, 120)
shopTitle.Font = Enum.Font.GothamBold
shopTitle.TextSize = 16
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.ZIndex = 13
shopTitle.Parent = shopPanel

local shopHint = Instance.new("TextLabel")
shopHint.Size = UDim2.new(1, -16, 0, 18)
shopHint.Position = UDim2.new(0, 8, 0, 30)
shopHint.BackgroundTransparency = 1
shopHint.Text = "Weapons and power-ups"
shopHint.TextColor3 = Color3.fromRGB(180, 180, 190)
shopHint.Font = Enum.Font.Gotham
shopHint.TextSize = 12
shopHint.TextXAlignment = Enum.TextXAlignment.Left
shopHint.ZIndex = 13
shopHint.Parent = shopPanel

local shopStatusLabel = Instance.new("TextLabel")
shopStatusLabel.Size = UDim2.new(1, -16, 0, 24)
shopStatusLabel.Position = UDim2.new(0, 8, 1, -28)
shopStatusLabel.BackgroundTransparency = 1
shopStatusLabel.Text = ""
shopStatusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
shopStatusLabel.Font = Enum.Font.Gotham
shopStatusLabel.TextSize = 12
shopStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
shopStatusLabel.ZIndex = 13
shopStatusLabel.Parent = shopPanel

local activeShopTab = "Weapons"

local shopTabsFrame = Instance.new("Frame")
shopTabsFrame.Size = UDim2.new(1, -16, 0, 28)
shopTabsFrame.Position = UDim2.new(0, 8, 0, 50)
shopTabsFrame.BackgroundTransparency = 1
shopTabsFrame.Parent = shopPanel

local function makeShopButton(parent, y, labelText)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -16, 0, 34)
	button.Position = UDim2.new(0, 8, 0, y)
	button.BackgroundColor3 = Color3.fromRGB(44, 44, 56)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = labelText
	button.AutoButtonColor = true
	button.ZIndex = 13
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

local shopConfig = CombatConfig.Shop or {}
local function makeShopTab(x, text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -4, 1, 0)
	button.Position = UDim2.new(x, 0, 0, 0)
	button.BackgroundColor3 = Color3.fromRGB(44, 44, 56)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.Text = text
	button.ZIndex = 13
	button.Parent = shopTabsFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

local weaponsTabButton = makeShopTab(0, "WEAPONS")
local powerupsTabButton = makeShopTab(0.5, "POWER-UPS")

local shopWeaponsFrame = Instance.new("Frame")
shopWeaponsFrame.Size = UDim2.new(1, 0, 0, 118)
shopWeaponsFrame.Position = UDim2.new(0, 0, 0, 84)
shopWeaponsFrame.BackgroundTransparency = 1
shopWeaponsFrame.Parent = shopPanel

local shopPowerupsFrame = Instance.new("Frame")
shopPowerupsFrame.Size = UDim2.new(1, 0, 0, 118)
shopPowerupsFrame.Position = UDim2.new(0, 0, 0, 84)
shopPowerupsFrame.BackgroundTransparency = 1
shopPowerupsFrame.Visible = false
shopPowerupsFrame.Parent = shopPanel

local shopWeaponButton = makeShopButton(shopWeaponsFrame, 0, ("Bat  -  $%d"):format(shopConfig.Weapon or 0))
local shopSwordButton = makeShopButton(shopWeaponsFrame, 38, ("Sword  -  $%d"):format(shopConfig.Sword or 0))
local shopPistolButton = makeShopButton(shopWeaponsFrame, 76, ("Pistol  -  $%d"):format(shopConfig.Pistol or 0))

local shopHealthButton = makeShopButton(shopPowerupsFrame, 0, ("Health Pack  -  $%d"):format(shopConfig.HealthPack or 0))
local shopShieldButton = makeShopButton(shopPowerupsFrame, 38, ("Shield  -  $%d"):format(shopConfig.Shield or 0))
local shopPotionButton = makeShopButton(shopPowerupsFrame, 76, ("Stamina Potion  -  $%d"):format(shopConfig.StaminaPotion or 0))

local function updateShopTabs()
	local weaponsActive = activeShopTab == "Weapons"
	shopWeaponsFrame.Visible = weaponsActive
	shopPowerupsFrame.Visible = not weaponsActive
	weaponsTabButton.BackgroundColor3 = weaponsActive and Color3.fromRGB(74, 74, 92) or Color3.fromRGB(44, 44, 56)
	powerupsTabButton.BackgroundColor3 = weaponsActive and Color3.fromRGB(44, 44, 56) or Color3.fromRGB(74, 74, 92)
end

weaponsTabButton.MouseButton1Click:Connect(function()
	activeShopTab = "Weapons"
	updateShopTabs()
end)

powerupsTabButton.MouseButton1Click:Connect(function()
	activeShopTab = "PowerUps"
	updateShopTabs()
end)

updateShopTabs()

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
G - Grab + Suplex
Q - Dodge
Shift (hold) - Sprint
E - Pick Up Item
1 / 2 / 3 - Switch Inventory Slot
F - Throw Held Item
R - Drop Held Item
B - Open Shop (Weapons / Power-Ups)]]
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
waitingLabel.Text = "Team size: 0/4"
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
local currentMoney = 0
local currentStamina = 100
local maxStamina = 100
local currentWave = 0
local shopStatusToken = 0

local function setShopVisible(visible)
	local allow = visible and _G.GameState == "Playing"
	shopPanel.Visible = allow
	if allow then
		_G.MouseFree = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		if _G.GameState == "Playing" then
			_G.MouseFree = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
	end
end

local function setShopStatus(text, isError)
	shopStatusToken = shopStatusToken + 1
	local token = shopStatusToken
	shopStatusLabel.Text = text or ""
	shopStatusLabel.TextColor3 = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(180, 220, 255)
	if text and text ~= "" then
		task.delay(2.5, function()
			if shopStatusToken == token then
				shopStatusLabel.Text = ""
			end
		end)
	end
end

shopWeaponButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("Weapon")
end)

shopSwordButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("Sword")
end)

shopPistolButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("Pistol")
end)

shopHealthButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("HealthPack")
end)

shopShieldButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("Shield")
end)

shopPotionButton.MouseButton1Click:Connect(function()
	ShopPurchaseEvent:FireServer("StaminaPotion")
end)

ShopResultEvent.OnClientEvent:Connect(function(success, message)
	setShopStatus(message or "", not success)
end)

shopToggleTouchButton.MouseButton1Click:Connect(function()
	if _G.GameState ~= "Playing" then
		setShopStatus("Shop opens during a match.", true)
		return
	end
	setShopVisible(not shopPanel.Visible)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		if _G.GameState ~= "Playing" then
			setShopStatus("Shop opens during a match.", true)
			return
		end
		setShopVisible(not shopPanel.Visible)
	end
end)

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------

-- Game state changes
GameStateEvent.OnClientEvent:Connect(function(state, data)
	if state == "GameStart" then
		_G.GameState = "Playing"
		setMusicState("Playing")
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
		waitingLabel.Text = "Team size: 0/4"
		backgroundOverlay.BackgroundTransparency = 0.35

		-- Hide game over screen
		gameOverScreen.Visible = false
		gameOverScreen.BackgroundTransparency = 1
		setShopVisible(false)
		shopToggleTouchButton.Visible = UserInputService.TouchEnabled
		shopPromptLabel.Text = UserInputService.TouchEnabled and "Tap SHOP button to open Shop" or "Press B to open Shop"
		setShopStatus("", false)

		-- Re-lock mouse for gameplay
		_G.MouseFree = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false

		-- Reset UI
		currentScore = 0
		scoreLabel.Text = "SCORE: 0"
		currentMoney = 0
		moneyLabel.Text = "$0"
		comboLabel.Text = ""
		comboSubLabel.Text = ""
		crosshairFrame.Visible = false

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
		setMusicState("GameOver")
		local finalScore = data or currentScore
		finalScoreLabel.Text = "FINAL SCORE: " .. tostring(finalScore)
		gameOverScreen.Visible = true
		gameOverScreen.BackgroundTransparency = 0.3
		TweenService:Create(gameOverScreen, TweenInfo.new(1), {BackgroundTransparency = 0.3}):Play()

		-- Unlock mouse so player can click Play Again
		_G.MouseFree = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		setShopVisible(false)
		shopToggleTouchButton.Visible = false
		crosshairFrame.Visible = false
	end
end)

TeamStatusEvent.OnClientEvent:Connect(function(activeCount, maxPlayers, overflow)
	local text = string.format("Team size: %d/%d", activeCount or 0, maxPlayers or 4)
	if overflow and overflow > 0 then
		text = text .. string.format("  (%d spectating)", overflow)
	end
	waitingLabel.Text = text
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

MoneyEvent.OnClientEvent:Connect(function(totalMoney, delta, reason)
	currentMoney = totalMoney or currentMoney
	moneyLabel.Text = "$" .. tostring(currentMoney)
	if delta and delta > 0 then
		task.spawn(function()
			moneyLabel.TextSize = 31
			TweenService:Create(moneyLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back), {TextSize = 26}):Play()
		end)
	end
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

task.spawn(function()
	local staminaEvent = ReplicatedStorage:WaitForChild("StaminaUpdate", 10)
	if not staminaEvent then
		staminaEvent = Instance.new("BindableEvent")
		staminaEvent.Name = "StaminaUpdate"
		staminaEvent.Parent = ReplicatedStorage
	end

	staminaEvent.Event:Connect(function(current, max)
		currentStamina = current or currentStamina
		maxStamina = max or maxStamina
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

	local staminaPercent = maxStamina > 0 and math.clamp(currentStamina / maxStamina, 0, 1) or 0
	staminaFill.Size = UDim2.new(staminaPercent, 0, 1, 0)
	staminaFill.BackgroundColor3 = Color3.fromRGB(
		math.floor(60 + 100 * (1 - staminaPercent)),
		math.floor(130 + 90 * staminaPercent),
		255
	)
	staminaLabel.Text = math.floor(currentStamina) .. " / " .. math.floor(maxStamina)
end)

print("[BrawlAlley] UIController loaded")
