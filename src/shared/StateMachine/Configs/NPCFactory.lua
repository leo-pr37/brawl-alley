local BaseConfig = require(script.Parent.NPCBaseConfig)
local Utility = require(script.Parent.Utility) -- Utility should have a deepCopy/clone function
local UniqueStatesFolder = script.Parent.Parent.States.UniqueNPC -- Folder for specialized states

-- Define specialized config modifications
local CONFIG_MODS = {
	-- Melee NPC: Overrides Attack with TankAttack, adds Stunned
	["Melee"] = function(baseConfig)
		local config = Utility.deepCopy(baseConfig)
		config.Attack = require(UniqueStatesFolder.TankAttack) -- Unique implementation
		config.Stunned = require(UniqueStatesFolder.Stunned)
		return config
	end,

	-- Ranged NPC: Overrides Chase with RangedChase
	["RangedModelName"] = function(baseConfig)
		local config = Utility.deepCopy(baseConfig)
		config.Chase = require(UniqueStatesFolder.RangedChase)
		return config
	end,

	-- Other NPC Types...
}

local NPCFactory = {}

function NPCFactory.get(npcModel)
	local npcName = npcModel:GetAttribute("NPCType")
	local modifier = CONFIG_MODS[npcName]

	if modifier then
		-- Apply modifications to a fresh copy of the base config
		return modifier(BaseConfig)
	end

	-- Return the standard base config if no specialization is needed
	return BaseConfig
end

return NPCFactory