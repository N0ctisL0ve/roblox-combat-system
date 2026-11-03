--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))

local EffectsController = {}

local SHAKE_BINDING = "CombatCameraShake"
local EFFECT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local random = Random.new()
local shakeBound = false
local shakeIntensity = 0
local shakeEndsAt = 0
local camera: Camera? = nil

local function createAnchor(position: Vector3): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = "CombatFx"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	return anchor
end

-- TODO: one part per sound and burst is wasteful, pool these before a full server
local function burst(position: Vector3, color: Color3)
	local anchor = createAnchor(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = EFFECT_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.15, 0.32)
	emitter.Speed = NumberRange.new(6, 13)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.45, 0.05)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(14)

	Debris:AddItem(anchor, 0.8)
end

-- bound above the default camera step, otherwise the shake adds up every frame
local function bindShake()
	if shakeBound then
		return
	end
	shakeBound = true

	RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		camera = cam

		if os.clock() >= shakeEndsAt then
			shakeIntensity = 0
			return
		end

		local strength = shakeIntensity * 0.25
		cam.CFrame = cam.CFrame
			* CFrame.new(
				random:NextNumber(-strength, strength),
				random:NextNumber(-strength, strength),
				0
			)
			* CFrame.Angles(0, 0, math.rad(random:NextNumber(-1, 1) * shakeIntensity))
	end)
end

function EffectsController.Init(): ()
	bindShake()
end

function EffectsController.PlaySound3D(soundId: string, position: Vector3, volume: number?): ()
	if soundId == "" then
		return
	end
	local anchor = createAnchor(position)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.65
	sound.RollOffMaxDistance = 90
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 3)
end

function EffectsController.ShakeCamera(intensity: number, duration: number): ()
	shakeIntensity = math.max(shakeIntensity, intensity)
	shakeEndsAt = math.max(shakeEndsAt, os.clock() + duration)
	bindShake()
end

-- called on input, before the server says anything
function EffectsController.Swing(soundId: string, origin: Vector3, direction: Vector3): ()
	EffectsController.PlaySound3D(soundId, origin, 0.5)

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end

	local arc = createAnchor(origin)
	arc.Name = "CombatSwingArc"
	arc.Material = Enum.Material.Neon
	arc.Color = Color3.fromRGB(210, 230, 255)
	arc.Transparency = 0.55
	arc.Size = Vector3.new(4.5, 0.35, 3)
	arc.CFrame = CFrame.lookAt(origin + flat * 2.2, origin + flat * 6)

	TweenService:Create(arc, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(5.6, 0.35, 4.2),
	}):Play()

	Debris:AddItem(arc, 0.16)
end

function EffectsController.Hitmarker(position: Vector3, blocked: boolean): ()
	burst(position, if blocked then Color3.fromRGB(120, 180, 255) else Color3.fromRGB(255, 205, 110))
	EffectsController.ShakeCamera(if blocked then 0.35 else 0.65, 0.08)
	EffectsController.PlaySound3D(
		if blocked then CombatConfig.Effects.BlockSoundId else CombatConfig.Effects.HitmarkerSoundId,
		position
	)
end

function EffectsController.Hurt(): ()
	EffectsController.ShakeCamera(1.15, 0.1)
	local localCharacter = Players.LocalPlayer.Character
	local root = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		EffectsController.PlaySound3D(CombatConfig.Effects.HurtSoundId, root.Position)
	end
end

return EffectsController
