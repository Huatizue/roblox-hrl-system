--!strict

local ArmIK = {}

export type Joints = {
	shoulderC0: CFrame,
	shoulderC1: CFrame,
	elbowC0: CFrame,
	elbowC1: CFrame,
	wristC0: CFrame,
	wristC1: CFrame,
	grip: CFrame,
}

local EPSILON = 1e-4
local X_AXIS = Vector3.new(1, 0, 0)

local function basis(axis: Vector3, reference: Vector3): CFrame
	local x = axis.Unit
	local y = reference - x * reference:Dot(x)
	if y.Magnitude < EPSILON then
		y = if math.abs(x.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(0, 0, 1)
		y = y - x * y:Dot(x)
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.new(0, 0, 0), x, y, x:Cross(y))
end

local function orient(boneLocal: Vector3, bone: Vector3, hinge: Vector3): CFrame
	return basis(bone, hinge) * basis(boneLocal, X_AXIS):Inverse()
end

local function place(rotation: CFrame, localPoint: Vector3, point: Vector3): CFrame
	return CFrame.new(point - rotation:VectorToWorldSpace(localPoint)) * rotation
end

function ArmIK.solve(joints: Joints, target: Vector3, pole: Vector3): (CFrame, CFrame, CFrame, CFrame)
	local shoulder = joints.shoulderC0.Position
	local upperBone = joints.elbowC0.Position - joints.shoulderC1.Position
	local gripInLower = (joints.wristC0 * joints.wristC1:Inverse() * joints.grip).Position
	local lowerBone = gripInLower - joints.elbowC1.Position
	local upperLength = upperBone.Magnitude
	local lowerLength = lowerBone.Magnitude

	local toTarget = target - shoulder
	local reach = math.clamp(
		toTarget.Magnitude,
		math.abs(upperLength - lowerLength) + EPSILON,
		upperLength + lowerLength - EPSILON
	)
	local forward = if toTarget.Magnitude > EPSILON then toTarget.Unit else Vector3.new(0, -1, 0)

	local toPole = pole - shoulder
	local bend = toPole - forward * toPole:Dot(forward)
	if bend.Magnitude < EPSILON then
		bend = forward:Cross(Vector3.new(1, 0, 0))
		if bend.Magnitude < EPSILON then
			bend = forward:Cross(Vector3.new(0, 0, 1))
		end
	end
	bend = bend.Unit

	local cosine = math.clamp(
		(upperLength * upperLength + reach * reach - lowerLength * lowerLength) / (2 * upperLength * reach),
		-1,
		1
	)
	local sine = math.sqrt(1 - cosine * cosine)
	local elbow = shoulder + (forward * cosine + bend * sine) * upperLength
	local hand = shoulder + forward * reach
	local hinge = bend:Cross(forward)

	local upperRotation = orient(upperBone, elbow - shoulder, hinge)
	local upperArm = place(upperRotation, joints.shoulderC1.Position, shoulder)
	local shoulderTransform = joints.shoulderC0:Inverse() * upperArm * joints.shoulderC1

	local elbowJoint = (upperArm * joints.elbowC0).Position
	local lowerRotation = orient(lowerBone, hand - elbowJoint, hinge)
	local lowerArm = place(lowerRotation, joints.elbowC1.Position, elbowJoint)
	local elbowTransform = joints.elbowC0:Inverse() * upperArm:Inverse() * lowerArm * joints.elbowC1

	return shoulderTransform, elbowTransform, upperArm, lowerArm
end

return ArmIK
