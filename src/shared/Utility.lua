-- ReplicatedStorage/Utility.lua
-- Small shared helpers used across server and shared code

local Utility = {}

-- Ensure a Model has PrimaryPart set. Tries preferredNames (array), then HumanoidRootPart, then first BasePart.
-- Returns true if PrimaryPart is set, false otherwise.
function Utility.ensurePrimaryPart(model, preferredNames)
    if not model or not model:IsA("Model") then return false end

    if model.PrimaryPart then
        return true
    end

    preferredNames = preferredNames or {"HumanoidRootPart"}

    for _, name in ipairs(preferredNames) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            model.PrimaryPart = part
            return true
        end
    end

    -- Fallback: pick the first BasePart found
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            model.PrimaryPart = child
            return true
        end
    end

    return false
end

return Utility
