-- ServerScriptService/Services/GameRulesService.lua
-- Example service that enforces simple game rules and exposes a small API

local GameRulesService = {}

function GameRulesService.Init()
    print("[GameRulesService] Init")
    -- Setup any state, default configs, or connections needed before Start
end

function GameRulesService.Start()
    print("[GameRulesService] Start")
    -- Start timers, connect events, etc.
end

function GameRulesService.Stop()
    print("[GameRulesService] Stop")
    -- Cleanup connections
end

-- Example public API
function GameRulesService.isPvPAllowed()
    return false
end

return GameRulesService
