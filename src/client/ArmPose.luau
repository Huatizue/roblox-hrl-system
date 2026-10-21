--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local ArmIK = require(Shared.ArmIK)

local MOUNT_NAME = "LauncherMount"
local SIDES = { "Right", "Left" }

local ArmPose = {}

local function findChild(parent: Instance?, name: string, class: string): any
	local child = parent and parent:FindFirstChild(name)
	if child and child:IsA(class) then
		return child
	end
	return nil
end

local function findJoint(parent: Instance?, name: string): any
	local joint = parent and parent:FindFirstChild(name)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

local function findAttachment(parent: Instance, name: string): Attachment?
	local found = parent:FindFirstChild(name, true)
	if found and found:IsA("Attachment") then
		return found
	end
	return nil
end

local function getLauncher(character: Model): Model?
	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			for _, model in tool:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart:FindFirstChild(MOUNT_NAME) then
					return model
				end
			end
		end
	end
	return nil
end

local function poseArm(character: Model, torso: BasePart, launcher: Model, side: string)
	local upperArm = findChild(character, `{side}UpperArm`, "BasePart")
	local lowerArm = findChild(character, `{side}LowerArm`, "BasePart")
	local hand = findChild(character, `{side}Hand`, "BasePart")
	local shoulder = findJoint(upperArm, `{side}Shoulder`)
	local elbow = findJoint(lowerArm, `{side}Elbow`)
	local wrist = findJoint(hand, `{side}Wrist`)
	local grip: Attachment? = findChild(hand, `{side}GripAttachment`, "Attachment")
	local target = findAttachment(launcher, `{side}Grip`)
	local pole = findAttachment(launcher, `{side}ElbowPole`)
	if not shoulder or not elbow or not wrist or not grip or not target or not pole then
		return
	end

	local torsoFrame = torso.CFrame
	local joints = {
		shoulderC0 = shoulder.C0,
		shoulderC1 = shoulder.C1,
		elbowC0 = elbow.C0,
		elbowC1 = elbow.C1,
		wristC0 = wrist.C0,
		wristC1 = wrist.C1,
		grip = grip.CFrame,
	}
	local targetPoint = torsoFrame:PointToObjectSpace(target.WorldPosition)
	local polePoint = torsoFrame:PointToObjectSpace(pole.WorldPosition)
	local shoulderTransform, elbowTransform = ArmIK.solve(joints, targetPoint, polePoint)
	shoulder.Transform = shoulderTransform
	elbow.Transform = elbowTransform
	wrist.Transform = CFrame.identity
end

local function onPreSimulation()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local torso = character and findChild(character, "UpperTorso", "BasePart")
		local launcher = character and torso and getLauncher(character)
		if character and torso and launcher then
			for _, side in SIDES do
				poseArm(character, torso, launcher, side)
			end
		end
	end
end

function ArmPose.start()
	RunService.PreSimulation:Connect(onPreSimulation)
end

return ArmPose
