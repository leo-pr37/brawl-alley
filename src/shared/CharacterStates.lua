--[[
	CharacterStates (Shared)
	State definitions for both players and enemies.
	Each state table has: enter, exit, update, lockDuration, canExit, canEnter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationManager = require(Shared:WaitForChild("AnimationManager"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))

local CharacterStates = {}

------------------------------------------------------------
-- ENEMY STATES
------------------------------------------------------------
CharacterStates.Enemy = {
	Idle = {
		enter = function(model, prevState, sm)
			AnimationManager.PlayEnemyLocomotion(model, sm:GetData("enemyType") or "Thug", false)
		end,
		update = function(model, dt, sm)
			AnimationManager.PlayEnemyLocomotion(model, sm:GetData("enemyType") or "Thug", false)
		end,
	},

	Walking = {
		enter = function(model, prevState, sm)
			AnimationManager.PlayEnemyLocomotion(model, sm:GetData("enemyType") or "Thug", true)
		end,
		update = function(model, dt, sm)
			AnimationManager.PlayEnemyLocomotion(model, sm:GetData("enemyType") or "Thug", true)
		end,
	},

	Attacking = {
		lockDuration = 0.4,
		enter = function(model, prevState, sm)
			-- Attack animation is played externally by doEnemyComboHit
		end,
		canExit = function(model, nextState)
			return nextState == "Dead" or nextState == "HitStun"
		end,
	},

	Taunting = {
		lockDuration = function(model, sm)
			return (sm:GetData("enemyType") == "Brawler") and 1.8 or 1.2
		end,
		enter = function(model, prevState, sm)
			-- Taunt animation is played externally by doEnemyTaunt
		end,
		canExit = function(model, nextState)
			return nextState == "Dead" or nextState == "HitStun"
		end,
	},

	HitStun = {
		lockDuration = 0.3,
		enter = function(model, prevState, sm)
			AnimationManager.PlayHitReaction(model, false)
		end,
	},

	Dead = {
		enter = function(model, prevState, sm)
			-- Death handled by humanoid.Died
		end,
		canExit = function()
			return false
		end,
	},
}

------------------------------------------------------------
-- PLAYER STATES
------------------------------------------------------------
CharacterStates.Player = {
	Idle = {
		enter = function(model, prevState, sm)
		end,
		update = function(model, dt, sm)
		end,
	},

	Walking = {
		enter = function(model, prevState, sm)
		end,
		update = function(model, dt, sm)
		end,
	},

	Sprinting = {
		enter = function(model, prevState, sm)
		end,
		update = function(model, dt, sm)
		end,
	},

	Attacking = {
		lockDuration = 0.25,
		enter = function(model, prevState, sm)
			-- Attack anim played by CombatController
		end,
		canExit = function(model, nextState)
			return nextState == "Dead" or nextState == "HitStun" or nextState == "Idle"
		end,
	},

	Grabbing = {
		lockDuration = CombatConfig.Grab and CombatConfig.Grab.ActionLockDuration or 0.6,
		enter = function(model, prevState, sm)
			AnimationManager.PlaySuplex(model)
		end,
		canExit = function(model, nextState)
			return nextState == "Dead" or nextState == "HitStun"
		end,
	},

	Blocking = {
		enter = function(model, prevState, sm)
			AnimationManager.PlayBlock(model)
		end,
		exit = function(model, nextState, sm)
			if nextState ~= "Dead" then
				AnimationManager.PlayUnblock(model)
			end
		end,
	},

	Dodging = {
		lockDuration = CombatConfig.DodgeIFrames,
		enter = function(model, prevState, sm)
			AnimationManager.PlayDodge(model)
		end,
		canExit = function(model, nextState)
			return nextState == "Dead"
		end,
	},

	HitStun = {
		lockDuration = 0.25,
		enter = function(model, prevState, sm)
			AnimationManager.PlayHitReaction(model, false)
		end,
	},

	Dead = {
		enter = function(model, prevState, sm)
			-- Handled by humanoid.Died
		end,
		canExit = function()
			return false
		end,
	},
}

return CharacterStates
