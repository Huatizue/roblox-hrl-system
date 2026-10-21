--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "HomingMissileRemotes"

local RELIABLE = { "Fire", "SetSteering", "Spawned", "Detonated" }
local UNRELIABLE = { "Aim", "Snapshot" }

export type Remotes = {
	Fire: RemoteEvent,
	SetSteering: RemoteEvent,
	Spawned: RemoteEvent,
	Detonated: RemoteEvent,
	Aim: UnreliableRemoteEvent,
	Snapshot: UnreliableRemoteEvent,
}

local Net = {}

local cached: Remotes? = nil

function Net.get(): Remotes
	if cached then
		return cached
	end

	local remotes = {}
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in RELIABLE do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
			remotes[name] = remote
		end
		for _, name in UNRELIABLE do
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = folder
			remotes[name] = remote
		end
		folder.Parent = ReplicatedStorage
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
		for _, name in RELIABLE do
			remotes[name] = folder:WaitForChild(name)
		end
		for _, name in UNRELIABLE do
			remotes[name] = folder:WaitForChild(name)
		end
	end

	cached = (remotes :: any) :: Remotes
	return cached :: Remotes
end

return Net
