--!strict

export type HitboxShape = "Box" | "Sphere"

export type AttackDefinition = {
	Id: string,
	Damage: number,
	Cooldown: number,
	ComboWindow: number,
	Hitstun: number,
	Knockback: number,
	HitboxShape: HitboxShape,
	HitboxSize: Vector3,
	HitboxOffset: CFrame,
	AnimationId: string,
	SwingSoundId: string,
	HitSoundId: string,
}

export type ComboConfig = {
	ResetTime: number,
	InputBufferWindow: number,
	MaxTargetsPerSwing: number,
	Chain: { AttackDefinition },
}

export type ValidationConfig = {
	BaseReachTolerance: number,
	TargetPadding: number,
	PingReachBudget: number,
	MaxPingCompensation: number,
	PingSafetyMultiplier: number,
	MaxAngleDegrees: number,
	PingAngleDegreesPerSecond: number,
	PingAngleBudgetDegrees: number,
	MinRequestInterval: number,
	MaxRequestsPerSecond: number,
	MaxPartsPerQuery: number,
}

export type RulesConfig = {
	FriendlyFire: boolean,
	BlockDamageMultiplier: number,
	BlockConeDegrees: number,
	InvulnerabilityAfterHit: number,
	KnockbackDuration: number,
	HitstopDuration: number,
	EffectRadius: number,
}

export type DebugConfig = {
	HitColor: Color3,
	MissColor: Color3,
	Transparency: number,
	Lifetime: number,
	MarkerSize: number,
	MarkerTransparency: number,
}

export type EffectsConfig = {
	HitmarkerSoundId: string,
	BlockSoundId: string,
	HurtSoundId: string,
}

export type Config = {
	DEBUG_HITBOXES: number,
	Combo: ComboConfig,
	Validation: ValidationConfig,
	Rules: RulesConfig,
	Debug: DebugConfig,
	Effects: EffectsConfig,
}

export type AttackRejectionReason = "RATE_LIMIT" | "LOCKED" | "INVALID"

export type AttackConfirmedPayload = {
	Attacker: Player,
	AttackId: string,
	ComboIndex: number,
	Origin: Vector3,
	Hit: boolean,
}

export type HitFeedbackPayload = {
	Attacker: Player,
	Target: Player?,
	Position: Vector3,
	Damage: number,
	Blocked: boolean,
	Killed: boolean,
}

-- types only, nothing to run
return {}
