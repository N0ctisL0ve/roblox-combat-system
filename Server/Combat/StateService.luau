--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local StateService = {}

export type CombatState = {
	IsAttacking: boolean,
	Stunned: boolean,
	Blocking: boolean,
	IFrames: boolean,
	ComboIndex: number,
	ComboExpiresAt: number,
	LastAttackClock: number,
	AttackEndsAt: number,
	StunEndsAt: number,
	IFramesEndAt: number,
	RequestTimes: { number },
}

local ATTR_ATTACKING = "IsAttacking"
local ATTR_STUNNED = "Stunned"
local ATTR_BLOCKING = "Blocking"
local ATTR_IFRAMES = "IFrames"

-- the real state. Player attributes below are a copy for the client, and attribute
-- writes from a client never reach the server anyway.
local states: { [Player]: CombatState } = {}

local function newState(): CombatState
	return {
		IsAttacking = false,
		Stunned = false,
		Blocking = false,
		IFrames = false,
		ComboIndex = 0,
		ComboExpiresAt = 0,
		LastAttackClock = 0,
		AttackEndsAt = 0,
		StunEndsAt = 0,
		IFramesEndAt = 0,
		RequestTimes = {},
	}
end

local function replicate(player: Player, state: CombatState): ()
	player:SetAttribute(ATTR_ATTACKING, state.IsAttacking)
	player:SetAttribute(ATTR_STUNNED, state.Stunned)
	player:SetAttribute(ATTR_BLOCKING, state.Blocking)
	player:SetAttribute(ATTR_IFRAMES, state.IFrames)
end

function StateService.Get(player: Player): CombatState
	local state = states[player]
	if not state then
		state = newState()
		states[player] = state
		replicate(player, state)
	end
	return state
end

function StateService.SetAttacking(player: Player, attacking: boolean, duration: number?): ()
	local state = StateService.Get(player)
	state.IsAttacking = attacking
	state.AttackEndsAt = if attacking then os.clock() + (duration or 0) else 0

	if attacking then
		StateService.SetBlocking(player, false)
	end

	replicate(player, state)
end

function StateService.SetStunned(player: Player, duration: number): ()
	local state = StateService.Get(player)
	state.Stunned = true
	state.StunEndsAt = os.clock() + duration
	StateService.SetBlocking(player, false)
	replicate(player, state)
end

function StateService.SetIFrames(player: Player, duration: number): ()
	local state = StateService.Get(player)
	state.IFrames = true
	state.IFramesEndAt = os.clock() + duration
	replicate(player, state)
end

function StateService.SetBlocking(player: Player, blocking: boolean): ()
	local state = StateService.Get(player)
	if state.Blocking == blocking then
		return
	end

	state.Blocking = blocking
	replicate(player, state)
end

function StateService.ClearAttack(player: Player): ()
	local state = StateService.Get(player)
	if not state.IsAttacking and state.ComboIndex == 0 then
		return
	end
	state.IsAttacking = false
	state.AttackEndsAt = 0
	state.ComboIndex = 0
	state.ComboExpiresAt = 0
	replicate(player, state)
end

function StateService.IsLocked(player: Player): boolean
	local state = StateService.Get(player)
	return state.IsAttacking or state.Stunned or state.Blocking
end

function StateService.Reset(player: Player): ()
	local state = StateService.Get(player)
	state.IsAttacking = false
	state.Stunned = false
	state.Blocking = false
	state.IFrames = false
	state.ComboIndex = 0
	state.ComboExpiresAt = 0
	state.AttackEndsAt = 0
	state.StunEndsAt = 0
	state.IFramesEndAt = 0
	table.clear(state.RequestTimes)
	replicate(player, state)
end

local function tickStates(): ()
	local now = os.clock()

	for player, state in states do
		local changed = false

		if state.IsAttacking and now >= state.AttackEndsAt then
			state.IsAttacking = false
			changed = true
		end
		if state.Stunned and now >= state.StunEndsAt then
			state.Stunned = false
			changed = true
		end
		if state.IFrames and now >= state.IFramesEndAt then
			state.IFrames = false
			changed = true
		end

		if changed then
			replicate(player, state)
		end
	end
end

function StateService.Start(): ()
	-- 30 Hz, the client gates its next swing on these attributes
	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator < 1 / 30 then
			return
		end
		accumulator = 0
		tickStates()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

return StateService
