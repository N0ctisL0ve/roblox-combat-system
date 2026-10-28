--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))
local CombatMath = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatMath"))
local HitboxDebug = require(script.Parent:WaitForChild("HitboxDebug"))

local HitboxValidator = {}

type AttackShape = {
	HitboxShape: string,
	HitboxSize: Vector3,
	HitboxOffset: CFrame,
}

export type TargetHit = {
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Distance: number,
}

export type ValidationResult = {
	HitboxCFrame: CFrame,
	HitboxSize: Vector3,
	ForwardExtent: number,
	PingAllowance: number,
	Targets: { TargetHit },
	Rejected: { Vector3 },
}

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = false
overlapParams.MaxParts = CombatConfig.Validation.MaxPartsPerQuery

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function resolveCharacter(part: BasePart): (Model?, Humanoid?)
	local node: Instance? = part.Parent
	while node and node ~= Workspace do
		local humanoid = node:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return node :: Model, humanoid :: Humanoid
		end
		node = node.Parent
	end
	return nil, nil
end

-- the target's own parts do not count as a wall
local function isRayClear(origin: Vector3, destination: Vector3, attackerCharacter: Model, targetCharacter: Model): boolean
	raycastParams.FilterDescendantsInstances = { attackerCharacter }
	local result = Workspace:Raycast(origin, destination - origin, raycastParams)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

-- body first, then head, a low ledge otherwise blocks hits that look like they land
local function hasLineOfSight(origin: Vector3, attackerCharacter: Model, targetCharacter: Model, targetRoot: BasePart): boolean
	if isRayClear(origin, targetRoot.Position, attackerCharacter, targetCharacter) then
		return true
	end

	local head = targetCharacter:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return isRayClear(origin, head.Position, attackerCharacter, targetCharacter)
	end

	return false
end

local function isHostile(attacker: Player, targetCharacter: Model): boolean
	if CombatConfig.Rules.FriendlyFire then
		return true
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer or targetPlayer == attacker then
		return true
	end

	local attackerTeam = attacker.Team
	local targetTeam = targetPlayer.Team
	return attackerTeam == nil or targetTeam == nil or attackerTeam ~= targetTeam
end

function HitboxValidator.Validate(attackerPlayer: Player, attackerCharacter: Model, attack: AttackShape): ValidationResult?
	local attackerRoot = getRoot(attackerCharacter)
	if not attackerRoot then
		return nil
	end

	local attackerHumanoid = attackerCharacter:FindFirstChildOfClass("Humanoid")
	if not attackerHumanoid or not attackerHumanoid:IsA("Humanoid") or attackerHumanoid.Health <= 0 then
		return nil
	end

	local hitboxCFrame = attackerRoot.CFrame * attack.HitboxOffset
	local hitboxSize = attack.HitboxSize
	-- root to the front face of the box
	local forwardExtent = hitboxSize.Z * 0.5 + math.max(-attack.HitboxOffset.Position.Z, 0)

	-- clamp it, otherwise a fake ping inflates reach
	local ping = math.clamp(
		attackerPlayer:GetNetworkPing() * CombatConfig.Validation.PingSafetyMultiplier,
		0,
		0.5
	)
	local reachAllowance = CombatMath.pingReachAllowance(
		ping,
		CombatConfig.Validation.PingReachBudget,
		CombatConfig.Validation.MaxPingCompensation
	)
	local angleAllowance = math.min(
		ping * CombatConfig.Validation.PingAngleDegreesPerSecond,
		CombatConfig.Validation.PingAngleBudgetDegrees
	)

	local maxDistance = forwardExtent
		+ CombatConfig.Validation.BaseReachTolerance
		+ CombatConfig.Validation.TargetPadding
		+ reachAllowance
	local halfAngle = CombatConfig.Validation.MaxAngleDegrees + angleAllowance

	local attackerLook = attackerRoot.CFrame.LookVector

	overlapParams.FilterDescendantsInstances = { attackerCharacter }

	local parts: { BasePart }
	if attack.HitboxShape == "Sphere" then
		parts = Workspace:GetPartBoundsInRadius(hitboxCFrame.Position, hitboxSize.X * 0.5, overlapParams)
	else
		parts = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
	end

	local targets: { TargetHit } = {}
	local rejected: { Vector3 } = {}
	local visited: { [Model]: boolean } = {}

	for _, part in parts do
		if #targets >= CombatConfig.Combo.MaxTargetsPerSwing then
			break
		end

		local targetCharacter, targetHumanoid = resolveCharacter(part)
		if not targetCharacter or not targetHumanoid or visited[targetCharacter] then
			continue
		end

		visited[targetCharacter] = true
		if targetCharacter == attackerCharacter or targetHumanoid.Health <= 0 or not isHostile(attackerPlayer, targetCharacter) then
			continue
		end

		local targetRoot = getRoot(targetCharacter)
		if not targetRoot then
			continue
		end

		local offset = targetRoot.Position - attackerRoot.Position
		local distance = offset.Magnitude
		local withinReach = distance <= maxDistance
		local withinAngle = CombatMath.isWithinCone(attackerLook, offset, halfAngle)
		local visible = withinReach and withinAngle and hasLineOfSight(attackerRoot.Position, attackerCharacter, targetCharacter, targetRoot)

		if visible then
			table.insert(targets, {
				Character = targetCharacter,
				Humanoid = targetHumanoid,
				Root = targetRoot,
				Distance = distance,
			})
		else
			table.insert(rejected, targetRoot.Position)
		end
	end

	local result: ValidationResult = {
		HitboxCFrame = hitboxCFrame,
		HitboxSize = hitboxSize,
		ForwardExtent = forwardExtent,
		PingAllowance = reachAllowance,
		Targets = targets,
		Rejected = rejected,
	}

	if CombatConfig.DEBUG_HITBOXES == 1 then
		HitboxDebug.DrawHitbox(hitboxCFrame, hitboxSize, attack.HitboxShape, #targets > 0)
		for _, target in targets do
			HitboxDebug.DrawMarker(target.Root.Position, true)
		end
		for _, point in rejected do
			HitboxDebug.DrawMarker(point, false)
		end
	end

	return result
end

return HitboxValidator
