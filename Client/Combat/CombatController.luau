--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Remotes"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local CombatController = {}

type AttackDefinition = {
	Id: string,
	Cooldown: number,
	ComboWindow: number,
	AnimationId: string,
	SwingSoundId: string,
	HitSoundId: string,
}

type AttackConfirmedPayload = {
	Attacker: Player,
	AttackId: string,
	ComboIndex: number,
	Origin: Vector3,
	Hit: boolean,
}

type HitFeedbackPayload = {
	Attacker: Player,
	Target: Player?,
	Position: Vector3,
	Damage: number,
	Blocked: boolean,
	Killed: boolean,
}

local HITSTOP_SPEED = 0.1

local player = Players.LocalPlayer

local remotes: { [string]: RemoteEvent } = {
	AttackRequest = Remotes.Get(Remotes.Events.AttackRequest),
	SetBlocking = Remotes.Get(Remotes.Events.SetBlocking),
	AttackConfirmed = Remotes.Get(Remotes.Events.AttackConfirmed),
	AttackRejected = Remotes.Get(Remotes.Events.AttackRejected),
	HitFeedback = Remotes.Get(Remotes.Events.HitFeedback),
}

local character: Model? = nil
local trackCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local predictedCombo = 0
local comboExpiresAt = 0
local nextAttackAt = 0
local bufferedUntil = 0
local blockRequestAt = 0
local isBlocking = false
local initialized = false

local function findAttack(attackId: string): AttackDefinition?
	for _, attack in CombatConfig.Combo.Chain do
		if attack.Id == attackId then
			return attack
		end
	end
	return nil
end

-- Animation objects in ReplicatedStorage.Combat.Animations are named after the attack
-- id, so the asset ids never end up in the config
local function resolveAnimationId(attackId: string, fallbackId: string): string
	local folder = ReplicatedStorage:FindFirstChild("Combat")
	local animations = folder and folder:FindFirstChild("Animations")
	if animations then
		local animation = animations:FindFirstChild(attackId)
		if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
			return animation.AnimationId
		end
	end
	return fallbackId
end

local function getAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	return nil
end

local function playAnimation(model: Model, attackId: string): ()
	local attack = findAttack(attackId)
	if not attack then
		return
	end

	local animationId = resolveAnimationId(attackId, attack.AnimationId)
	if animationId == "" then
		return
	end

	local animator = getAnimator(model)
	if not animator then
		return
	end

	local perAnimator = trackCache[animator]
	if not perAnimator then
		perAnimator = {}
		trackCache[animator] = perAnimator
	end

	local track = perAnimator[attackId]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		perAnimator[attackId] = track
	end

	if track.IsPlaying then
		track:Stop(0.05)
	end
	track:Play(0.06)
end

local function stopPredictedAnimation(): ()
	local model = character
	local animator = model and getAnimator(model)
	if not animator then
		return
	end
	local perAnimator = trackCache[animator]
	if not perAnimator then
		return
	end
	for _, track in perAnimator do
		if track.IsPlaying then
			track:Stop(0.05)
		end
	end
end

local function setTracksSpeed(model: Model, speed: number): ()
	local animator = getAnimator(model)
	if not animator then
		return
	end
	local perAnimator = trackCache[animator]
	if not perAnimator then
		return
	end
	for _, track in perAnimator do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
end

-- slow both tracks and restore on a timer, a chain otherwise leaves them stuck at 0.1
local function applyHitstop(models: { Model }): ()
	local duration = CombatConfig.Rules.HitstopDuration
	for _, model in models do
		setTracksSpeed(model, HITSTOP_SPEED)
	end
	task.delay(duration, function()
		for _, model in models do
			setTracksSpeed(model, 1)
		end
	end)
end

local function isLocked(): boolean
	return player:GetAttribute("IsAttacking") == true
		or player:GetAttribute("Stunned") == true
		or player:GetAttribute("Blocking") == true
end

local function canAttack(now: number): boolean
	return now >= nextAttackAt and not isLocked()
end

local function isStunnedOrBlocking(): boolean
	return player:GetAttribute("Stunned") == true or player:GetAttribute("Blocking") == true
end

local function startAttack(): ()
	local now = os.clock()
	if now > comboExpiresAt then
		predictedCombo = 0
	end

	predictedCombo += 1
	local chain = CombatConfig.Combo.Chain
	if predictedCombo > #chain then
		predictedCombo = 1
	end

	local attack: AttackDefinition = chain[predictedCombo]
	nextAttackAt = now + attack.Cooldown
	comboExpiresAt = now + CombatConfig.Combo.ResetTime

	remotes.AttackRequest:FireServer()

	-- prediction, play it now. The server reply only corrects the combo index.
	local model = character
	if model then
		playAnimation(model, attack.Id)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			EffectsController.Swing(attack.SwingSoundId, root.Position, root.CFrame.LookVector)
		end
	end
end

local function requestAttack(): ()
	local now = os.clock()
	if canAttack(now) then
		bufferedUntil = 0
		startAttack()
		return
	end

	-- only buffer clicks inside the window. The extra 0.35s is because the server clears
	-- IsAttacking on its next tick, which lands after our local cooldown ends.
	local attackEndAt = nextAttackAt
	if attackEndAt - now <= CombatConfig.Combo.InputBufferWindow and not isStunnedOrBlocking() then
		bufferedUntil = attackEndAt + 0.35
	end
end

local function setBlocking(blocking: boolean): ()
	if isBlocking == blocking then
		return
	end
	isBlocking = blocking
	blockRequestAt = os.clock()
	remotes.SetBlocking:FireServer(blocking)
end

local function isAttackInput(input: InputObject): boolean
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return true
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		return true
	end
	return input.KeyCode == Enum.KeyCode.ButtonR2
end

local function isBlockInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.F
end

local function onCharacterAdded(newCharacter: Model): ()
	character = newCharacter
	trackCache = setmetatable({}, { __mode = "k" }) :: any
	predictedCombo = 0
	comboExpiresAt = 0
	nextAttackAt = 0
	bufferedUntil = 0
	isBlocking = false
	blockRequestAt = 0
end

function CombatController.Init(): ()
	if initialized or RunService:IsServer() then
		return
	end
	initialized = true

	EffectsController.Init()

	local existing = player.Character
	if existing then
		onCharacterAdded(existing)
	end
	player.CharacterAdded:Connect(onCharacterAdded)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if isAttackInput(input) then
			requestAttack()
		elseif isBlockInput(input) then
			setBlocking(true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if isBlockInput(input) then
			setBlocking(false)
		end
	end)

	remotes.AttackConfirmed.OnClientEvent:Connect(function(payload: AttackConfirmedPayload)
		if payload.Attacker == player then
			if payload.ComboIndex ~= predictedCombo then
				predictedCombo = payload.ComboIndex
			end
			comboExpiresAt = os.clock() + CombatConfig.Combo.ResetTime
			return
		end

		local attackerCharacter = payload.Attacker.Character
		if attackerCharacter then
			playAnimation(attackerCharacter, payload.AttackId)
		end

		local attack = findAttack(payload.AttackId)
		if attack then
			local root = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart")
			local look = Vector3.new(0, 0, -1)
			if root and root:IsA("BasePart") then
				look = root.CFrame.LookVector
			end
			EffectsController.Swing(attack.SwingSoundId, payload.Origin, look)
		end
	end)

	remotes.AttackRejected.OnClientEvent:Connect(function(_reason: string)
		stopPredictedAnimation()
		predictedCombo = math.max(predictedCombo - 1, 0)
		nextAttackAt = math.min(nextAttackAt, os.clock() + 0.05)
	end)

	remotes.HitFeedback.OnClientEvent:Connect(function(payload: HitFeedbackPayload)
		local mine = character
		local isInvolved = payload.Attacker == player or payload.Target == player

		if payload.Attacker == player then
			EffectsController.Hitmarker(payload.Position, payload.Blocked)
		elseif payload.Target == player then
			EffectsController.Hurt()
		end

		if isInvolved then
			local models: { Model } = {}
			if mine then
				table.insert(models, mine)
			end
			local opponent = if payload.Attacker == player then payload.Target else payload.Attacker
			local opponentCharacter = opponent and opponent.Character
			if opponentCharacter then
				table.insert(models, opponentCharacter)
			end
			applyHitstop(models)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()

		if bufferedUntil > 0 then
			if now > bufferedUntil then
				bufferedUntil = 0
			elseif now >= nextAttackAt and not isLocked() then
				bufferedUntil = 0
				startAttack()
			end
		end

		-- our block flag is optimistic, pull it back from the attribute every so often
		if now - blockRequestAt >= 0.4 then
			local serverBlocking = player:GetAttribute("Blocking") == true
			if serverBlocking ~= isBlocking then
				isBlocking = serverBlocking
			end
		end
	end)
end

return CombatController
