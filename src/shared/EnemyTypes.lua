-- EnemyTypes: Definitions for all enemy variants
local EnemyTypes = {}

EnemyTypes.Types = {
	Thug = {
		Name = "Thug",
		Health = 40,
		Damage = 8,
		WalkSpeed = 12,
		AttackRange = 5,
		AttackCooldown = 1.2,
		AggroRange = 40,
		Color = BrickColor.new("Bright red"),
		ScaleMultiplier = 1.0,
		ScoreValue = 100,
		KnockbackResist = 0,
		Description = "Basic street thug. Slow but steady.",
		-- Combo: 2-hit (hook + hook)
		ComboHits = 2,
		ComboCooldown = 0.5, -- time between combo hits
		ComboDamageMultipliers = {1.0, 1.2},
		-- Taunt
		TauntText = "You're dead meat!",
		TauntCooldown = 6, -- minimum seconds between taunts
		TauntChance = 0.6, -- high chance to taunt
	},
	Brawler = {
		Name = "Brawler",
		Health = 70,
		Damage = 12,
		WalkSpeed = 10,
		AttackRange = 6,
		AttackCooldown = 1.5,
		AggroRange = 35,
		Color = BrickColor.new("Really red"),
		ScaleMultiplier = 1.3,
		ScoreValue = 200,
		KnockbackResist = 0.4,
		Description = "Big and tough. Hits hard, takes a beating.",
		-- Combo: 3-hit (haymaker + bodyslam + ground pound)
		ComboHits = 3,
		ComboCooldown = 0.7,
		ComboDamageMultipliers = {1.0, 1.3, 1.8},
		-- Taunt
		TauntText = "I'll crush you!",
		TauntCooldown = 7,
		TauntChance = 0.55,
	},
	Speedster = {
		Name = "Speedster",
		Health = 25,
		Damage = 6,
		WalkSpeed = 22,
		AttackRange = 4.5,
		AttackCooldown = 0.7,
		AggroRange = 50,
		Color = BrickColor.new("Bright yellow"),
		ScaleMultiplier = 0.85,
		ScoreValue = 150,
		KnockbackResist = 0,
		Description = "Fast and annoying. Attacks quickly.",
		-- Combo: 4-hit (jab + jab + jab + spinning kick)
		ComboHits = 4,
		ComboCooldown = 0.25,
		ComboDamageMultipliers = {0.8, 0.8, 0.8, 1.5},
		-- Taunt
		TauntText = "Can't touch this!",
		TauntCooldown = 5,
		TauntChance = 0.65,
	},
}

EnemyTypes.LevelOrder = {"Alley", "Subway", "Rooftops", "Warehouse", "FightClub"}
EnemyTypes.DefaultLevel = "Alley"

-- Level definitions: each level has handcrafted opening waves and endless scaling weights.
EnemyTypes.Levels = {
	Alley = {
		DisplayName = "Alley District",
		WaveTemplates = {
			[1] = {{Type = "Thug", Count = 3}},
			[2] = {{Type = "Thug", Count = 4}, {Type = "Speedster", Count = 1}},
			[3] = {{Type = "Thug", Count = 3}, {Type = "Speedster", Count = 2}},
			[4] = {{Type = "Thug", Count = 2}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 1}},
			[5] = {{Type = "Thug", Count = 3}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 3}},
			[6] = {{Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 4}},
			[7] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 3}},
			[8] = {{Type = "Brawler", Count = 4}, {Type = "Speedster", Count = 5}},
		},
		ProceduralWeights = {Thug = 0.50, Brawler = 0.40, Speedster = 0.30},
	},
	Subway = {
		DisplayName = "Subway Yard",
		WaveTemplates = {
			[1] = {{Type = "Thug", Count = 4}},
			[2] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 1}},
			[3] = {{Type = "Thug", Count = 5}, {Type = "Speedster", Count = 1}},
			[4] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 2}},
			[5] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 2}},
			[6] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 2}},
			[7] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 3}},
			[8] = {{Type = "Thug", Count = 6}, {Type = "Brawler", Count = 4}, {Type = "Speedster", Count = 3}},
		},
		ProceduralWeights = {Thug = 0.70, Brawler = 0.45, Speedster = 0.25},
	},
	Rooftops = {
		DisplayName = "Rooftop Run",
		WaveTemplates = {
			[1] = {{Type = "Speedster", Count = 3}},
			[2] = {{Type = "Speedster", Count = 4}, {Type = "Thug", Count = 2}},
			[3] = {{Type = "Speedster", Count = 4}, {Type = "Brawler", Count = 1}},
			[4] = {{Type = "Speedster", Count = 5}, {Type = "Thug", Count = 2}, {Type = "Brawler", Count = 1}},
			[5] = {{Type = "Speedster", Count = 5}, {Type = "Brawler", Count = 2}},
			[6] = {{Type = "Speedster", Count = 6}, {Type = "Thug", Count = 3}, {Type = "Brawler", Count = 2}},
			[7] = {{Type = "Speedster", Count = 7}, {Type = "Thug", Count = 3}, {Type = "Brawler", Count = 2}},
			[8] = {{Type = "Speedster", Count = 7}, {Type = "Thug", Count = 4}, {Type = "Brawler", Count = 3}},
		},
		ProceduralWeights = {Thug = 0.35, Brawler = 0.40, Speedster = 0.60},
	},
	Warehouse = {
		DisplayName = "Warehouse",
		WaveTemplates = {
			[1] = {{Type = "Thug", Count = 4}},
			[2] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 1}},
			[3] = {{Type = "Thug", Count = 4}, {Type = "Speedster", Count = 2}},
			[4] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 2}},
			[5] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 2}},
			[6] = {{Type = "Thug", Count = 6}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 2}},
			[7] = {{Type = "Thug", Count = 6}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 3}},
			[8] = {{Type = "Thug", Count = 7}, {Type = "Brawler", Count = 4}, {Type = "Speedster", Count = 3}},
		},
		ProceduralWeights = {Thug = 0.65, Brawler = 0.45, Speedster = 0.25},
	},
	FightClub = {
		DisplayName = "Fight Club",
		WaveTemplates = {
			[1] = {{Type = "Thug", Count = 3}, {Type = "Speedster", Count = 1}},
			[2] = {{Type = "Thug", Count = 3}, {Type = "Brawler", Count = 1}, {Type = "Speedster", Count = 1}},
			[3] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 1}, {Type = "Speedster", Count = 2}},
			[4] = {{Type = "Thug", Count = 3}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 2}},
			[5] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 2}, {Type = "Speedster", Count = 2}},
			[6] = {{Type = "Thug", Count = 4}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 2}},
			[7] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 3}, {Type = "Speedster", Count = 3}},
			[8] = {{Type = "Thug", Count = 5}, {Type = "Brawler", Count = 4}, {Type = "Speedster", Count = 3}},
		},
		ProceduralWeights = {Thug = 0.45, Brawler = 0.55, Speedster = 0.35},
	},
}

-- Compatibility for existing code paths that still read EnemyTypes.Waves.
EnemyTypes.Waves = EnemyTypes.Levels[EnemyTypes.DefaultLevel].WaveTemplates

function EnemyTypes.GetLevel(levelKey)
	return EnemyTypes.Levels[levelKey] or EnemyTypes.Levels[EnemyTypes.DefaultLevel]
end

local function cloneWave(waveDef)
	local copy = {}
	for i, group in ipairs(waveDef) do
		copy[i] = {
			Type = group.Type,
			Count = group.Count,
		}
	end
	return copy
end

-- After wave 8, generate procedural waves
function EnemyTypes.GetWave(waveNumber, levelKey)
	local level = EnemyTypes.GetLevel(levelKey)
	local waves = level.WaveTemplates

	if waveNumber <= #waves then
		return cloneWave(waves[waveNumber])
	end

	-- Procedural wave generation for endless mode
	local weights = level.ProceduralWeights
	local thugs = math.max(1, math.floor(waveNumber * (weights.Thug or 0.5)))
	local brawlers = math.max(1, math.floor(waveNumber * (weights.Brawler or 0.4)))
	local speedsters = math.max(1, math.floor(waveNumber * (weights.Speedster or 0.3)))
	return {
		{Type = "Thug", Count = thugs},
		{Type = "Brawler", Count = brawlers},
		{Type = "Speedster", Count = speedsters},
	}
end

-- Health scaling per wave
function EnemyTypes.GetHealthMultiplier(waveNumber)
	return 1 + (waveNumber - 1) * 0.1
end

return EnemyTypes
