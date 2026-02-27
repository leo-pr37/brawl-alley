--// PlayerController.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StateManager = require(game.ServerScriptService.Server.Systems.StateManager)
local BaseStateMachine = require(ReplicatedStorage.Shared.StateMachine.StateMachine)
local PlayerConfig = require(ReplicatedStorage.Shared.StateMachine.Configs.PlayerConfig) --player specific states
local AnimationController = require(script.Parent.Parent.Systems.AnimationController)


local PlayerController = {}

function PlayerController.init()

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local sm = BaseStateMachine.new(character, PlayerConfig)
			StateManager.register(character, sm)
			sm:changeState("Idle")
			AnimationController.loadAnimations(character, "Player")
			print("[PlayerController] Registered Player:", character.Name)
		end)
	end)

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local attackEvent = remotes:WaitForChild("PlayerAttack")

	attackEvent.OnServerEvent:Connect(function(player)
		local char = player.Character
		if not char then return end

		local sm = StateManager.getStateMachine(char)
		if not sm then
			warn("[PlayerController] No state machine for", player.Name)
			return
		end
		
		-- Debug print to confirm receipt
		print("[PlayerController] Attack event from", player.Name, "current state:", sm.state)


		if sm.state == "Idle" then
			sm:changeState("Attack")
		elseif sm.state == "Attack" then
			sm.inputQueued = true
		end
	end)
end

return PlayerController

