--!strict

local CombatMath = {}

local EPSILON = 1e-3
local DEG_TO_RAD = math.pi / 180

function CombatMath.flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < EPSILON then
		return Vector3.zero
	end
	return flat.Unit
end

function CombatMath.horizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function CombatMath.dotFlat(a: Vector3, b: Vector3): number
	local flatA = CombatMath.flatten(a)
	local flatB = CombatMath.flatten(b)
	if flatA.Magnitude < EPSILON or flatB.Magnitude < EPSILON then
		return 0
	end
	return flatA:Dot(flatB)
end

function CombatMath.isWithinCone(lookDirection: Vector3, toTarget: Vector3, halfAngleDegrees: number): boolean
	local flatTarget = CombatMath.flatten(toTarget)
	if flatTarget.Magnitude < EPSILON then
		return true
	end
	return CombatMath.dotFlat(lookDirection, flatTarget) >= math.cos(halfAngleDegrees * DEG_TO_RAD)
end

-- capped, a spoofed ping should not buy extra range
function CombatMath.pingReachAllowance(pingSeconds: number, studsPerSecond: number, maxStuds: number): number
	local clampedPing = math.max(pingSeconds, 0)
	return math.min(clampedPing * studsPerSecond, maxStuds)
end

return CombatMath
