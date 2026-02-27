--// GameController.lua
-- The main entry point for initializing all server systems.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Require modules
local PlayerController = require(script.Parent.Controllers.PlayerController)
local NPCController = require(script.Parent.Controllers.NPCController)
local NPCSpawner = require(script.Parent.Controllers.NPCSpawner)
local StateManager = require(script.Parent.Systems.StateManager)
local ServiceManager = require(script.Parent.Systems.ServiceManager)
local GameRulesService = require(script.Parent.Services.GameRulesService)
local SmokeTestService = require(script.Parent.Services.SmokeTestService)

-- Initialize systems
-- Register and initialize services (Service-oriented pattern)
ServiceManager.register("GameRules", GameRulesService)
ServiceManager.register("SmokeTest", SmokeTestService)
ServiceManager.initAll()
ServiceManager.startAll()

StateManager.init()
PlayerController.init()
NPCController.init()
NPCSpawner.init()

print("[GameController] Initialization complete.")

-- The one and only update loop
RunService.Heartbeat:Connect(function(dt)
	-- This single call updates ALL registered NPCs and Players
	StateManager.updateAll(dt) 
end)

-- Optional: on server shutdown, stop services (RunService:IsRunning is usually true in studio)
game:BindToClose(function()
    ServiceManager.stopAll()
end)