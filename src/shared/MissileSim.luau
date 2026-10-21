--!strict

local Config = require(script.Parent.Config)
local Guidance = require(script.Parent.Guidance)

local MissileSim = {}

export type TargetGuide = {
	kind: "Target",
	position: Vector3,
	velocity: Vector3,
	visible: boolean,
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

local function updateSeeker(state: State, target: TargetGuide, dt: number, cfg: Config.Config): boolean
	if not state.locked then
		return false
	end

	local toTarget = target.position - state.position
	local range = toTarget.Magnitude
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

	local last = state.lastTargetVelocity
	if last ~= nil then
		local raw = (target.velocity - last) / dt
		local k = cfg.TargetAccelerationSmoothing
		state.targetAcceleration = state.targetAcceleration * k + raw * (1 - k)
	end
	state.lastTargetVelocity = target.velocity
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
			targetPosition = guide.position,
			targetVelocity = guide.velocity,
			targetAcceleration = state.targetAcceleration,
			navigationConstant = cfg.NavigationConstant,
			pursuitGain = cfg.PursuitGain,
		})
	end
	return Guidance.commandToLineOfSight(
		state.position,
		state.velocity,
		guide.origin,
		guide.direction,
		cfg.CursorLookahead,
		cfg.CursorPursuitGain
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
	local lateral = ZERO
	state.guided = command ~= nil
	if command ~= nil and state.age > cfg.ArmingDelay then
		command -= gravity
		local authority = math.clamp((state.speed / cfg.MaxSpeed) ^ 2, cfg.MinControlAuthority, 1)
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
	state.speed = speed
	state.velocity = velocity.Unit * speed
	state.position += state.velocity * dt

	if state.age >= cfg.MaxLifetime then
		state.alive = false
		state.deathReason = "Expired"
	elseif state.age > cfg.BurnTime and speed < cfg.MinSpeed then
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
