-- ServerScriptService/Systems/ServiceManager.lua
-- Simple service registry and lifecycle manager

local ServiceManager = {}
local services = {}

-- Register a service table under a name. Service table may implement Init, Start, Stop.
function ServiceManager.register(name, service)
    if not name or not service then return end
    services[name] = service
    print("[ServiceManager] Registered:", name)
end

function ServiceManager.get(name)
    return services[name]
end

-- Call Init on all registered services (safe-protected)
function ServiceManager.initAll()
    for name, svc in pairs(services) do
        if type(svc.Init) == "function" then
            print("[ServiceManager] Init:", name)
            local ok, err = pcall(svc.Init)
            if not ok then
                warn("[ServiceManager] Init failed for ", name, err)
            end
        end
    end
end

-- Call Start on all registered services
function ServiceManager.startAll()
    for name, svc in pairs(services) do
        if type(svc.Start) == "function" then
            print("[ServiceManager] Start:", name)
            local ok, err = pcall(svc.Start)
            if not ok then
                warn("[ServiceManager] Start failed for ", name, err)
            end
        end
    end
end

-- Call Stop on all registered services
function ServiceManager.stopAll()
    for name, svc in pairs(services) do
        if type(svc.Stop) == "function" then
            local ok, err = pcall(svc.Stop)
            if not ok then
                warn("[ServiceManager] Stop failed for ", name, err)
            end
        end
    end
end

return ServiceManager
