--!strict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))

local HitboxDebug = {}

local DEBUG_FOLDER = "CombatDebug"
local cachedFolder: Folder? = nil

local function getFolder(): Folder
	local known = cachedFolder
	if known and known.Parent then
		return known
	end

	local existing = Workspace:FindFirstChild(DEBUG_FOLDER)
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = DEBUG_FOLDER
		created.Parent = Workspace
		folder = created
	end

	cachedFolder = folder
	return folder
end

local function makePart(name: string, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	return part
end

-- the real query volume, green if anything got hit
function HitboxDebug.DrawHitbox(cframe: CFrame, size: Vector3, shape: string, hit: boolean): ()
	if CombatConfig.DEBUG_HITBOXES ~= 1 then
		return
	end

	local part = makePart("Hitbox", hit and CombatConfig.Debug.HitColor or CombatConfig.Debug.MissColor, CombatConfig.Debug.Transparency)
	part.CFrame = cframe
	part.Size = size

	if shape == "Sphere" then
		local diameter = math.min(size.X, size.Y, size.Z)
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(diameter, diameter, diameter)
	end

	part.Parent = getFolder()
	Debris:AddItem(part, CombatConfig.Debug.Lifetime)
end

function HitboxDebug.DrawMarker(position: Vector3, hit: boolean): ()
	if CombatConfig.DEBUG_HITBOXES ~= 1 then
		return
	end

	local marker = makePart("TargetMarker", hit and CombatConfig.Debug.HitColor or CombatConfig.Debug.MissColor, CombatConfig.Debug.MarkerTransparency)
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.one * CombatConfig.Debug.MarkerSize
	marker.CFrame = CFrame.new(position)
	marker.Parent = getFolder()
	Debris:AddItem(marker, CombatConfig.Debug.Lifetime)
end

function HitboxDebug.Clear(): ()
	local existing = Workspace:FindFirstChild(DEBUG_FOLDER)
	if existing then
		existing:ClearAllChildren()
	end
end

return HitboxDebug
