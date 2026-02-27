--// PlayerCombat.client.lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local attackEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerAttack")

local debounce = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if debounce then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		debounce = true

		-- Fire to server
		attackEvent:FireServer()

		-- Small local cooldown for responsiveness
		task.delay(0.2, function()
			debounce = false
		end)
	end
end)