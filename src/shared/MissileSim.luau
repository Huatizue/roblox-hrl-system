--!strict

local Config = require(script.Parent.Config)
local Guidance = require(script.Parent.Guidance)

local MissileSim = {}

export type TargetGuide = {
	kind: "Target",
	position: Vector3,
	velocity: Vector3,
	visible: boolean,
	assured: boolean?,
	aimOffset: Vector3?,
}

export type RayGuide = {
	kind: "Ray",
	origin: Vector3,
	direction: Vector3,
}

export type Guide = TargetGuide | RayGuide

export type DeathReason = "Expired" | "Stalled"

export type State = {
	position: Vector3,
	velocity: Vector3,
	speed: number,
	age: number,
	locked: boolean,
	hiddenTime: number,
	targetAcceleration: Vector3,
	lastTargetVelocity: Vector3?,
	guided: boolean,
	lateralAcceleration: Vector3,
	alive: boolean,
	deathReason: DeathReason?,
}

local ZERO = Vector3.new(0, 0, 0)

function MissileSim.new(origin: Vector3, direction: Vector3, config: Config.Config?): State
	local cfg = config or Config
	local heading = direction.Unit
	return {
		position = origin,
		velocity = heading * cfg.LaunchSpeed,
		speed = cfg.LaunchSpeed,
		age = 0,
		locked = true,
		hiddenTime = 0,
		targetAcceleration = ZERO,
		lastTargetVelocity = nil,
		guided = false,
		lateralAcceleration = ZERO,
		alive = true,
		deathReason = nil,
	}
end

local function updateTargetAcceleration(state: State, target: TargetGuide, dt: number, cfg: Config.Config)
	local last = state.lastTargetVelocity
	if last ~= nil then
		local raw = (target.velocity - last) / dt
		local k = cfg.TargetAccelerationSmoothing
		state.targetAcceleration = state.targetAcceleration * k + raw * (1 - k)
	end
	state.lastTargetVelocity = target.velocity
end

local function turnToward(vector: Vector3, direction: Vector3, maxAngle: number): Vector3
	local current = vector.Unit
	local desired = direction.Unit
	local angle = math.acos(math.clamp(current:Dot(desired), -1, 1))
	if angle < 1e-4 then
		return desired * vector.Magnitude
	end
	local axis = current:Cross(desired)
	if axis.Magnitude < 1e-6 then
		axis = current:Cross(if math.abs(current.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0))
	end
	local rotation = CFrame.fromAxisAngle(axis.Unit, math.min(angle, maxAngle))
	return rotation:VectorToWorldSpace(current) * vector.Magnitude
end

local function updateSeeker(state: State, target: TargetGuide, dt: number, cfg: Config.Config): boolean
	if not state.locked then
		return false
	end

	local toTarget = target.position - state.position
	local range = toTarget.Magnitude
	if target.aimOffset and state.age > cfg.ArmingDelay then
		if (toTarget + target.aimOffset):Dot(state.velocity) < 0 then
			state.locked = false
			return false
		end
	end
	if target.assured then
		updateTargetAcceleration(state, target, dt, cfg)
		return true
	end
	if range > cfg.SeekerRange then
		state.locked = false
		return false
	end

	if state.age > cfg.ArmingDelay and range > 1e-3 then
		local cosine = math.clamp(toTarget.Unit:Dot(state.velocity.Unit), -1, 1)
		if math.deg(math.acos(cosine)) > cfg.SeekerFieldOfView then
			state.locked = false
			return false
		end
	end

	if target.visible then
		state.hiddenTime = 0
	else
		state.hiddenTime += dt
		if state.hiddenTime > cfg.LockLossTimeout then
			state.locked = false
			return false
		end
	end

	updateTargetAcceleration(state, target, dt, cfg)
	return true
end

local function steeringCommand(state: State, guide: Guide?, dt: number, cfg: Config.Config): Vector3?
	if guide == nil then
		return nil
	end
	if guide.kind == "Target" then
		if not updateSeeker(state, guide, dt, cfg) then
			return nil
		end
		return Guidance.command(cfg.GuidanceLaw :: Guidance.Law, {
			missilePosition = state.position,
			missileVelocity = state.velocity,
			targetPosition = guide.position + (guide.aimOffset or ZERO),
			targetVelocity = guide.velocity,
			targetAcceleration = state.targetAcceleration,
			navigationConstant = cfg.NavigationConstant,
			pursuitGain = cfg.PursuitGain,
			pathLookahead = cfg.PathLookahead,
			previousTurn = state.lateralAcceleration,
		})
	end
	return Guidance.commandToLineOfSight(
		state.position,
		state.velocity,
		guide.origin,
		guide.direction,
		cfg.CursorLookahead,
		cfg.CursorPursuitGain,
		state.lateralAcceleration
	)
end

function MissileSim.step(state: State, dt: number, guide: Guide?, config: Config.Config?): State
	local cfg = config or Config
	if not state.alive then
		return state
	end

	state.age += dt
	local heading = state.velocity / state.speed
	local gravity = Vector3.new(0, -cfg.Gravity, 0)

	local command = steeringCommand(state, guide, dt, cfg)
	local assured = guide ~= nil and guide.kind == "Target" and guide.assured == true and state.locked
	local lateral = ZERO
	state.guided = command ~= nil
	if command ~= nil and state.age > cfg.ArmingDelay then
		command -= gravity
		local authority = math.clamp((state.speed / cfg.MaxSpeed) ^ 2, cfg.MinControlAuthority, 1)
		if assured then
			authority = 1
		end
		lateral = Guidance.limit(command, heading, cfg.MaxLateralAcceleration * authority)
	end
	state.lateralAcceleration = lateral

	local speed = state.speed
	if state.age <= cfg.BurnTime then
		speed += cfg.BoostAcceleration * dt
	else
		speed -= speed * cfg.DragCoefficient * dt
	end
	speed -= lateral.Magnitude * cfg.InducedDragCoefficient * speed * dt
	speed = math.clamp(speed, 1e-3, cfg.MaxSpeed)

	local velocity = state.velocity + (lateral + gravity) * dt
	if velocity.Magnitude < 1e-3 then
		velocity = heading
	end

	if assured and guide ~= nil and guide.kind == "Target" and state.age > cfg.ArmingDelay then
		local toTarget = guide.position - state.position
		local range = toTarget.Magnitude
		if range < cfg.TerminalRange and range > 1e-3 then
			local aim = toTarget + guide.velocity * (range / math.max(speed, 1))
			velocity = turnToward(velocity, aim, math.rad(cfg.TerminalTurnRate) * dt)
		end
	end
	state.speed = speed
	state.velocity = velocity.Unit * speed
	state.position += state.velocity * dt

	if state.age >= cfg.MaxLifetime * (if assured then 3 else 1) then
		state.alive = false
		state.deathReason = "Expired"
	elseif not assured and state.age > cfg.BurnTime and speed < cfg.MinSpeed then
		state.alive = false
		state.deathReason = "Stalled"
	end

	return state
end

function MissileSim.closestApproach(a: Vector3, b: Vector3): (number, number)
	local segment = b - a
	local lengthSquared = segment:Dot(segment)
	local t = 0
	if lengthSquared > 1e-9 then
		t = math.clamp(-a:Dot(segment) / lengthSquared, 0, 1)
	end
	return (a + segment * t).Magnitude, t
end

function MissileSim.fuze(
	missileFrom: Vector3,
	missileTo: Vector3,
	targetFrom: Vector3,
	targetTo: Vector3,
	age: number,
	config: Config.Config?
): Vector3?
	local cfg = config or Config
	if age <= cfg.ArmingDelay then
		return nil
	end
	local distance, t = MissileSim.closestApproach(missileFrom - targetFrom, missileTo - targetTo)
	if distance <= cfg.ProximityFuzeRadius then
		return missileFrom:Lerp(missileTo, t)
	end
	return nil
end

return MissileSim
