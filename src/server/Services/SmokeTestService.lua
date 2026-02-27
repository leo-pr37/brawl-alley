-- ServerScriptService/Services/SmokeTestService.lua
-- Simple smoke test service to verify ServiceManager and GameRulesService are wired

local ServiceManager = require(script.Parent.Parent.Systems.ServiceManager)
local GameRulesService = require(script.Parent.GameRulesService)

local SmokeTestService = {}

function SmokeTestService.Init()
    print("[SmokeTest] Init")
end

function SmokeTestService.Start()
    print("[SmokeTest] Start")
    -- Simple assertions
    local gr = GameRulesService
    if not gr or type(gr.isPvPAllowed) ~= "function" then
        warn("[SmokeTest] GameRulesService missing API")
    else
        print("[SmokeTest] GameRulesService.isPvPAllowed =>", tostring(gr.isPvPAllowed()))
    end

    -- Verify ServiceManager.get works
    local svc = ServiceManager.get("GameRules")
    if svc == nil then
        warn("[SmokeTest] ServiceManager.get returned nil for GameRules")
    else
        print("[SmokeTest] ServiceManager.get returned GameRules service")
    end
end

function SmokeTestService.Stop()
    print("[SmokeTest] Stop")
end

return SmokeTestService
