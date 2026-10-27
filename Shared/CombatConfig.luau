--!strict

local CombatTypes = require(script.Parent.CombatTypes)

local CombatConfig: CombatTypes.Config = {
	-- 1 draws the hitbox parts on the server, 0 skips all of it
	DEBUG_HITBOXES = 1,

	Combo = {
		ResetTime = 0.9,
		-- clicks in the last 0.18s of a swing get queued instead of dropped
		InputBufferWindow = 0.18,
		MaxTargetsPerSwing = 3,
		Chain = {
			{
				Id = "M1_Left",
				Damage = 9,
				Cooldown = 0.34,
				ComboWindow = 0.62,
				Hitstun = 0.22,
				Knockback = 8,
				HitboxShape = "Box",
				-- a bit bigger than the animation, a moving target should still get caught
				HitboxSize = Vector3.new(5, 4.6, 8),
				HitboxOffset = CFrame.new(0, 0, -3),
				AnimationId = "",
				SwingSoundId = "",
				HitSoundId = "",
			},
			{
				Id = "M1_Right",
				Damage = 11,
				Cooldown = 0.36,
				ComboWindow = 0.62,
				Hitstun = 0.24,
				Knockback = 10,
				HitboxShape = "Box",
				HitboxSize = Vector3.new(5, 4.6, 8),
				HitboxOffset = CFrame.new(0, 0, -3),
				AnimationId = "",
				SwingSoundId = "",
				HitSoundId = "",
			},
			{
				Id = "M1_Heavy",
				Damage = 16,
				Cooldown = 0.52,
				ComboWindow = 0.75,
				Hitstun = 0.34,
				Knockback = 18,
				HitboxShape = "Sphere",
				HitboxSize = Vector3.new(10, 10, 10),
				HitboxOffset = CFrame.new(0, 0, -2.5),
				AnimationId = "",
				SwingSoundId = "",
				HitSoundId = "",
			},
		},
	},

	Validation = {
		BaseReachTolerance = 3,
		TargetPadding = 1.5,
		-- extra studs of reach per second of ping
		PingReachBudget = 32,
		MaxPingCompensation = 6,
		-- GetNetworkPing is one way, the budget below wants RTT
		PingSafetyMultiplier = 2,
		MaxAngleDegrees = 75,
		PingAngleDegreesPerSecond = 140,
		PingAngleBudgetDegrees = 18,
		MinRequestInterval = 0.09,
		MaxRequestsPerSecond = 8,
		MaxPartsPerQuery = 32,
	},

	Rules = {
		FriendlyFire = false,
		BlockDamageMultiplier = 0.2,
		BlockConeDegrees = 70,
		InvulnerabilityAfterHit = 0.18,
		KnockbackDuration = 0.14,
		HitstopDuration = 0.06,
		EffectRadius = 120,
	},

	Debug = {
		HitColor = Color3.fromRGB(80, 255, 120),
		MissColor = Color3.fromRGB(255, 70, 70),
		Transparency = 0.68,
		Lifetime = 0.35,
		MarkerSize = 1.1,
		MarkerTransparency = 0.25,
	},

	Effects = {
		HitmarkerSoundId = "",
		BlockSoundId = "",
		HurtSoundId = "",
	},
}

return CombatConfig
