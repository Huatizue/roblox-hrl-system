--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)

local MODEL_NAME = "Launcher"
local MOUNT_NAME = "LauncherMount"
local DEFAULT_TORSO_TWIST = 45

local LauncherRig = {}

type Restore = {
	instance: Instance,
	property: string,
	value: CFrame,
}

type Rigged = {
	mount: Weld,
	restore: { Restore },
}

local rigged: { [Model]: Rigged } = {}

local function getLauncherModel(tool: Tool): Model?
	local existing = tool:FindFirstChild(MODEL_NAME)
	if existing and existing:IsA("Model") then
		return existing
	end
	local assets = Shared:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(MODEL_NAME)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	model.Parent = tool
	return model
end

local function findAttachment(parent: Instance, name: string): Attachment?
	local found = parent:FindFirstChild(name, true)
	if found and found:IsA("Attachment") then
		return found
	end
	return nil
end

local function turnJoint(parent: Instance?, name: string, rotation: CFrame, restore: { Restore })
	local joint = parent and parent:FindFirstChild(name)
	local instance: any, property
	if joint and joint:IsA("Motor6D") then
		instance, property = joint, "C0"
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		instance, property = joint.Attachment0, "CFrame"
	else
		return
	end
	local value: CFrame = instance[property]
	table.insert(restore, { instance = instance, property = property, value = value })
	instance[property] = value * rotation
end

local function unrig(character: Model)
	local state = rigged[character]
	if not state then
		return
	end
	rigged[character] = nil
	state.mount:Destroy()
	for _, saved in state.restore do
		(saved.instance :: any)[saved.property] = saved.value
	end
end

local function rig(character: Model, tool: Tool)
	unrig(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local upperTorso = character:FindFirstChild("UpperTorso")
	if
		not humanoid
		or humanoid.RigType ~= Enum.HumanoidRigType.R15
		or not upperTorso
		or not upperTorso:IsA("BasePart")
	then
		return
	end
	local shoulder = findAttachment(upperTorso, "RightShoulderRigAttachment")
	local model = getLauncherModel(tool)
	local root = model and model.PrimaryPart
	local mountPoint = model and findAttachment(model, "ShoulderMount")
	if not shoulder or not model or not root or not mountPoint then
		return
	end

	local twistAttribute = model:GetAttribute("TorsoTwist")
	local twist = math.rad(if typeof(twistAttribute) == "number" then twistAttribute else DEFAULT_TORSO_TWIST)

	local restore: { Restore } = {}
	turnJoint(upperTorso, "Waist", CFrame.Angles(0, -twist, 0), restore)
	turnJoint(character:FindFirstChild("Head"), "Neck", CFrame.Angles(0, twist, 0), restore)

	local mount = Instance.new("Weld")
	mount.Name = MOUNT_NAME
	mount.Part0 = upperTorso
	mount.Part1 = root
	mount.C0 = CFrame.new(shoulder.Position) * CFrame.Angles(0, twist, 0)
	mount.C1 = root.CFrame:ToObjectSpace(mountPoint.WorldCFrame)
	mount.Parent = root

	rigged[character] = { mount = mount, restore = restore }
end

local function isLauncher(instance: Instance): boolean
	return instance:IsA("Tool") and instance.Name == Config.LauncherToolName
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if isLauncher(child) then
			rig(character, child :: Tool)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if isLauncher(child) then
			unrig(character)
		end
	end)
	character.Destroying:Connect(function()
		rigged[character] = nil
	end)
	local tool = character:FindFirstChild(Config.LauncherToolName)
	if tool and tool:IsA("Tool") then
		rig(character, tool)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

function LauncherRig.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			rigged[player.Character] = nil
		end
	end)
end

return LauncherRig
