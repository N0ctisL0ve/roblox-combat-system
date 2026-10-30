--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFolder = ReplicatedStorage:WaitForChild("Combat")
local CombatConfig = require(CombatFolder:WaitForChild("CombatConfig"))
local CombatMath = require(CombatFolder:WaitForChild("CombatMath"))
local Remotes = require(CombatFolder:WaitForChild("Remotes"))
local HitboxValidator = require(script.Parent:WaitForChild("HitboxValidator"))
local StateService = require(script.Parent:WaitForChild("StateService"))

local CombatService = {}

local remotes: { [string]: RemoteEvent } = Remotes.PrepareAll()

local function getRoot(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- sliding window, kills spam before it reaches the spatial query
local function consumeRequestBudget(state: any, now: number): boolean
	if now - state.LastAttackClock < CombatConfig.Validation.MinRequestInterval then
		return false
	end

	local times = state.RequestTimes
	while #times > 0 and now - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= CombatConfig.Validation.MaxRequestsPerSecond then
		return false
	end

	times[#times + 1] = now
	return true
end

local function broadcastNearby(remote: RemoteEvent, origin: Vector3, payload: any): ()
	local radius = CombatConfig.Rules.EffectRadius
	for _, other in Players:GetPlayers() do
		local root = getRoot(other.Character)
		if root and (root.Position - origin).Magnitude <= radius then
			remote:FireClient(other, payload)
		end
	end
end

-- LinearVelocity instead of BodyVelocity, the old one is deprecated and fights the physics solver
local function applyKnockback(attackerRoot: BasePart, targetRoot: BasePart, attack: any): ()
	local direction = CombatMath.flatten(targetRoot.Position - attackerRoot.Position)
	if direction.Magnitude < 1e-3 then
		return
	end

	local duration = CombatConfig.Rules.KnockbackDuration

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatKnockbackAttachment"
	attachment.Parent = targetRoot

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CombatKnockback"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = 1e5
	velocity.VectorVelocity = direction * attack.Knockback + Vector3.new(0, attack.Knockback * 0.15, 0)
	velocity.Parent = targetRoot

	Debris:AddItem(velocity, duration)
	Debris:AddItem(attachment, duration + 0.05)
end

local function resolveBlock(target: Player, targetRoot: BasePart, attackerRoot: BasePart): boolean
	local state = StateService.Get(target)
	if not state.Blocking then
		return false
	end
	return CombatMath.isWithinCone(targetRoot.CFrame.LookVector, attackerRoot.Position - targetRoot.Position, CombatConfig.Rules.BlockConeDegrees)
end

local function dealDamage(attacker: Player, attackerRoot: BasePart, targetHit: any, attack: any): ()
	local targetCharacter: Model = targetHit.Character
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local targetState = if targetPlayer then StateService.Get(targetPlayer) else nil

	-- one swing per target, i-frames cover the rest
	if targetState and targetState.IFrames then
		return
	end

	local damage: number = attack.Damage
	local blocked = false
	if targetPlayer then
		blocked = resolveBlock(targetPlayer, targetHit.Root, attackerRoot)
	end

	if blocked then
		damage *= CombatConfig.Rules.BlockDamageMultiplier
	end

	local humanoid: Humanoid = targetHit.Humanoid
	local wasAlive = humanoid.Health > 0
	humanoid:TakeDamage(damage)
	local killed = wasAlive and humanoid.Health <= 0

	if targetPlayer then
		StateService.SetIFrames(targetPlayer, CombatConfig.Rules.InvulnerabilityAfterHit)
		if not blocked then
			-- getting hit cancels their swing and locks them for Hitstun. WalkSpeed stays alone.
			StateService.ClearAttack(targetPlayer)
			StateService.SetStunned(targetPlayer, attack.Hitstun)
		end
	end

	if not blocked then
		applyKnockback(attackerRoot, targetHit.Root, attack)
	end

	local feedback = {
		Attacker = attacker,
		Target = targetPlayer,
		Position = targetHit.Root.Position,
		Damage = damage,
		Blocked = blocked,
		Killed = killed,
	}
	broadcastNearby(remotes.HitFeedback, targetHit.Root.Position, feedback)
end

local function onAttackRequest(player: Player): ()
	local character = player.Character
	local humanoid = getAliveHumanoid(character)
	local attackerRoot = getRoot(character)
	if not character or not humanoid or not attackerRoot then
		return
	end

	local state = StateService.Get(player)
	local now = os.clock()

	-- over the limit means silent drop, no reply for an exploiter to spam on
	if not consumeRequestBudget(state, now) then
		return
	end

	if StateService.IsLocked(player) then
		remotes.AttackRejected:FireClient(player, "LOCKED")
		return
	end

	if now > state.ComboExpiresAt then
		state.ComboIndex = 0
	end

	local chain = CombatConfig.Combo.Chain
	local index = state.ComboIndex + 1
	if index > #chain then
		index = 1
	end
	local attack = chain[index]

	local result = HitboxValidator.Validate(player, character, attack)
	if not result then
		remotes.AttackRejected:FireClient(player, "INVALID")
		return
	end

	state.ComboIndex = index
	state.ComboExpiresAt = now + attack.ComboWindow
	state.LastAttackClock = now
	StateService.SetAttacking(player, true, attack.Cooldown)

	local confirmed = {
		Attacker = player,
		AttackId = attack.Id,
		ComboIndex = index,
		Origin = result.HitboxCFrame.Position,
		Hit = #result.Targets > 0,
	}
	broadcastNearby(remotes.AttackConfirmed, result.HitboxCFrame.Position, confirmed)

	for _, targetHit in result.Targets do
		dealDamage(player, attackerRoot, targetHit, attack)
	end
end

local function onSetBlocking(player: Player, blocking: unknown): ()
	if type(blocking) ~= "boolean" then
		return
	end

	local state = StateService.Get(player)
	if state.Stunned or state.IsAttacking or state.IFrames then
		return
	end

	StateService.SetBlocking(player, blocking)
end

local function onCharacterAdded(player: Player, character: Model): ()
	StateService.Reset(player)
	character:WaitForChild("Humanoid")
end

local function onPlayerAdded(player: Player): ()
	StateService.Get(player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		StateService.Reset(player)
	end)

	local character = player.Character
	if character then
		onCharacterAdded(player, character)
	end
end

function CombatService.Init(): ()
	StateService.Start()

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	remotes.AttackRequest.OnServerEvent:Connect(onAttackRequest)
	remotes.SetBlocking.OnServerEvent:Connect(onSetBlocking)
end

return CombatService
