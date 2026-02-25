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

-- Ground item system
CombatConfig.Items = {
	PickupRange = 8,
	SpawnIntervalMin = 8,
	SpawnIntervalMax = 16,
	MaxGroundItems = 6,
	ItemUseInputCooldown = 0.25,
	Health = {
		HealAmount = 35,
	},
	Weapon = {
		SwingDamage = 30,
		SwingRange = 7,
		SwingCooldown = 0.7,
		ThrowDamage = 18,
		ThrowSpeed = 75,
		ThrowCooldown = 0.9,
		ProjectileLifetime = 4,
		KnockbackForce = 28,
	},
	Rock = {
		ThrowDamage = 22,
		ThrowSpeed = 90,
		ThrowCooldown = 0.6,
		ProjectileLifetime = 5,
	},
}

-- Audio (all IDs should be free-to-use assets)
CombatConfig.Audio = {
	Music = {
		-- Optional: set these to free Creator Store audio IDs to enable background music.
		-- Example format: "rbxassetid://1234567890"
		LobbyTrackId = "rbxassetid://130156110441976",
		BattleTrackId = "",
		Volume = 0.2,
	},
	SFX = {
		AttackLightId = "rbxasset://sounds/swordslash.wav",
		AttackHeavyId = "rbxasset://sounds/swordlunge.wav",
		HitId = "rbxasset://sounds/swordhit.wav",
		HurtId = "rbxasset://sounds/uuhhh.wav",
		BlockId = "rbxasset://sounds/swordhit.wav",
		PickupId = "rbxasset://sounds/button.wav",
		Volume = 0.45,
	},
}

return CombatConfig
