--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)

local MODEL_NAME = "Launcher"
local MOUNT_NAME = "LauncherMount"
local DEFAULT_TORSO_TWIST = 45

local LauncherRig = {}

type Rigged = {
	mount: Weld,
	iks: { IKControl },
	restore: { [Motor6D]: CFrame },
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

local function findMotor(parent: Instance?, name: string): Motor6D?
	local found = parent and parent:FindFirstChild(name)
	if found and found:IsA("Motor6D") then
		return found
	end
	return nil
end

local function makeArmIK(character: Model, humanoid: Humanoid, side: string, model: Model): IKControl?
	local upperArm = character:FindFirstChild(`{side}UpperArm`)
	local hand = character:FindFirstChild(`{side}Hand`)
	local effector = hand and findAttachment(hand, `{side}GripAttachment`)
	local target = findAttachment(model, `{side}Grip`)
	if not upperArm or not effector or not target then
		return nil
	end
	local ik = Instance.new("IKControl")
	ik.Name = `Launcher{side}ArmIK`
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = upperArm
	ik.EndEffector = effector
	ik.Target = target
	ik.Pole = findAttachment(model, `{side}ElbowPole`)
	ik.SmoothTime = 0.08
	ik.Parent = humanoid
	return ik
end

local function unrig(character: Model)
	local state = rigged[character]
	if not state then
		return
	end
	rigged[character] = nil
	state.mount:Destroy()
	for _, ik in state.iks do
		ik:Destroy()
	end
	for motor, c0 in state.restore do
		motor.C0 = c0
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

	local restore: { [Motor6D]: CFrame } = {}
	local waist = findMotor(upperTorso, "Waist")
	local neck = findMotor(character:FindFirstChild("Head"), "Neck")
	if waist then
		restore[waist] = waist.C0
		waist.C0 *= CFrame.Angles(0, -twist, 0)
	end
	if neck then
		restore[neck] = neck.C0
		neck.C0 *= CFrame.Angles(0, twist, 0)
	end

	local mount = Instance.new("Weld")
	mount.Name = MOUNT_NAME
	mount.Part0 = upperTorso
	mount.Part1 = root
	mount.C0 = CFrame.new(shoulder.Position) * CFrame.Angles(0, twist, 0)
	mount.C1 = root.CFrame:ToObjectSpace(mountPoint.WorldCFrame)
	mount.Parent = root

	local iks = {}
	for _, side in { "Right", "Left" } do
		local ik = makeArmIK(character, humanoid, side, model)
		if ik then
			table.insert(iks, ik)
		end
	end

	rigged[character] = { mount = mount, iks = iks, restore = restore }
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
