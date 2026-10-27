--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CombatRemotes"
local WAIT_TIMEOUT = 15

local Remotes = {}

Remotes.Events = table.freeze({
	AttackRequest = "AttackRequest",
	SetBlocking = "SetBlocking",
	AttackConfirmed = "AttackConfirmed",
	AttackRejected = "AttackRejected",
	HitFeedback = "HitFeedback",
})

local cachedFolder: Folder? = nil

local function getFolder(): Folder
	local known = cachedFolder
	if known and known.Parent then
		return known
	end

	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		local folder: Folder
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = ReplicatedStorage
			folder = created
		end
		cachedFolder = folder
		return folder
	end

	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(waited and waited:IsA("Folder"), `[Combat] ReplicatedStorage is missing the {FOLDER_NAME} folder`)
	local folder = waited :: Folder
	cachedFolder = folder
	return folder
end

-- server creates remotes on first use, client waits for them. Same call on both sides.
function Remotes.Get(name: string): RemoteEvent
	local parent = getFolder()

	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
		return remote
	end

	local waited = parent:WaitForChild(name, WAIT_TIMEOUT)
	assert(waited and waited:IsA("RemoteEvent"), `[Combat] RemoteEvent "{name}" not found`)
	return waited :: RemoteEvent
end

function Remotes.PrepareAll(): { [string]: RemoteEvent }
	local map: { [string]: RemoteEvent } = {}
	for _, name in Remotes.Events do
		map[name] = Remotes.Get(name)
	end
	return map
end

return Remotes
