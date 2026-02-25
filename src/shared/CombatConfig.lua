-- CombatConfig: All combat-related constants and tuning
local CombatConfig = {}

-- Player stats
CombatConfig.PlayerMaxHealth = 100
CombatConfig.PlayerWalkSpeed = 20
CombatConfig.PlayerJumpPower = 50

-- Attack definitions
CombatConfig.Attacks = {
	LightAttack = {
		Damage = 8,
		Range = 6,
		Cooldown = 0.35,
		KnockbackForce = 15,
		AnimDuration = 0.3,
		ComboWindow = 0.6, -- seconds to chain next hit
		HitboxSize = Vector3.new(5, 5, 5),
	},
	HeavyAttack = {
		Damage = 20,
		Range = 7,
		Cooldown = 0.8,
		KnockbackForce = 40,
		AnimDuration = 0.6,
		ChargeTime = 0.4, -- hold duration before release
		HitboxSize = Vector3.new(6, 5, 7),
	},
}

-- Combo system
CombatConfig.ComboMultipliers = {
	[1] = 1.0,
	[2] = 1.1,
	[3] = 1.25,
	[4] = 1.5,  -- finisher hit
}
CombatConfig.MaxComboHits = 4
CombatConfig.ComboResetTime = 2.0 -- seconds of no hits to reset combo counter

-- Block/Dodge
CombatConfig.BlockDamageReduction = 0.75
CombatConfig.DodgeIFrames = 0.4
CombatConfig.DodgeDistance = 20
CombatConfig.DodgeCooldown = 1.0

-- Score
CombatConfig.ScorePerKill = 100
CombatConfig.ScorePerHit = 10
CombatConfig.ComboScoreBonus = 50 -- per combo level

return CombatConfig
