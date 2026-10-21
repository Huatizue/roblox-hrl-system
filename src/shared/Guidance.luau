--!strict

local Guidance = {}

export type Law = "PurePursuit" | "ProportionalNavigation" | "AugmentedPN"

export type Input = {
	missilePosition: Vector3,
	missileVelocity: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3,
	targetAcceleration: Vector3?,
	navigationConstant: number,
	pursuitGain: number,
}

local EPSILON = 1e-6
local ZERO = Vector3.new(0, 0, 0)

local function perpendicular(v: Vector3, axis: Vector3): Vector3
	return v - axis * v:Dot(axis)
end

local function anyPerpendicular(v: Vector3): Vector3
	local helper = if math.abs(v.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	return v:Cross(helper).Unit
end

function Guidance.lineOfSight(input: Input): (Vector3, Vector3, number, number)
	local relativePosition = input.targetPosition - input.missilePosition
	local relativeVelocity = input.targetVelocity - input.missileVelocity
	local rangeSquared = relativePosition:Dot(relativePosition)
	if rangeSquared < EPSILON then
		return ZERO, ZERO, 0, 0
	end
	local range = math.sqrt(rangeSquared)
	local los = relativePosition / range
	local losRate = relativePosition:Cross(relativeVelocity) / rangeSquared
	local closingSpeed = -relativePosition:Dot(relativeVelocity) / range
	return los, losRate, closingSpeed, range
end

function Guidance.purePursuit(input: Input): Vector3
	local relativePosition = input.targetPosition - input.missilePosition
	local speed = input.missileVelocity.Magnitude
	if relativePosition.Magnitude < EPSILON or speed < EPSILON then
		return ZERO
	end
	local heading = input.missileVelocity / speed
	local los = relativePosition.Unit
	local turnDirection = perpendicular(los, heading)

	if los:Dot(heading) < 0 then
		local direction = if turnDirection.Magnitude > EPSILON then turnDirection.Unit else anyPerpendicular(heading)
		return direction * speed * input.pursuitGain * 4
	end

	local _, losRate = Guidance.lineOfSight(input)
	local followLos = losRate:Cross(heading) * speed
	return followLos + turnDirection * speed * input.pursuitGain
end

function Guidance.proportionalNavigation(input: Input): Vector3
	local los, losRate, closingSpeed = Guidance.lineOfSight(input)
	if closingSpeed <= 0 then
		return Guidance.purePursuit(input)
	end
	return losRate:Cross(los) * (input.navigationConstant * closingSpeed)
end

function Guidance.augmentedProportionalNavigation(input: Input): Vector3
	local command = Guidance.proportionalNavigation(input)
	local targetAcceleration = input.targetAcceleration
	if targetAcceleration == nil then
		return command
	end
	local los = Guidance.lineOfSight(input)
	return command + perpendicular(targetAcceleration, los) * (input.navigationConstant / 2)
end

function Guidance.commandToLineOfSight(
	missilePosition: Vector3,
	missileVelocity: Vector3,
	rayOrigin: Vector3,
	rayDirection: Vector3,
	lookahead: number,
	gain: number
): Vector3
	local alongRay = math.max((missilePosition - rayOrigin):Dot(rayDirection), 0)
	local aimPoint = rayOrigin + rayDirection * (alongRay + lookahead)
	return Guidance.purePursuit({
		missilePosition = missilePosition,
		missileVelocity = missileVelocity,
		targetPosition = aimPoint,
		targetVelocity = ZERO,
		navigationConstant = 0,
		pursuitGain = gain,
	})
end

local LAWS: { [Law]: (Input) -> Vector3 } = {
	PurePursuit = Guidance.purePursuit,
	ProportionalNavigation = Guidance.proportionalNavigation,
	AugmentedPN = Guidance.augmentedProportionalNavigation,
}

function Guidance.command(law: Law, input: Input): Vector3
	local fn = LAWS[law]
	assert(fn, `Unknown guidance law "{law}"`)
	return fn(input)
end

function Guidance.limit(command: Vector3, heading: Vector3, maxAcceleration: number): Vector3
	local lateral = perpendicular(command, heading)
	local magnitude = lateral.Magnitude
	if magnitude > maxAcceleration then
		return lateral * (maxAcceleration / magnitude)
	end
	return lateral
end

return Guidance
