--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)
local MissileSim = require(Shared.MissileSim)
local Net = require(Shared.Net)
local Targets = require(Shared.Targets)

local Warhead = require(script.Parent.Warhead)

export type Mode = "Cursor" | "Homing"

type Missile = {
	id: number,
	owner: Player,
	mode: Mode,
	sim: MissileSim.State,
	target: Instance?,
	targetPosition: Vector3?,
	targetVelocity: Vector3,
	targetVisible: boolean,
	seekerTimer: number,
}

type PlayerState = {
	lastFireTime: number,
	missiles: { Missile },
	steering: boolean,
	aimOrigin: Vector3?,
	aimDirection: Vector3?,
	lastAimTime: number,
}

local STEP = 1 / Config.SimulationRate
local MAX_STEPS_PER_FRAME = 8
local MAX_AIM_DISTANCE = 4000

local MissileService = {}

local remotes = Net.get()
local missiles: { [number]: Missile } = {}
local playerStates: { [Player]: PlayerState } = {}
local nextId = 0
local accumulator = 0
local snapshotTimer = 0

local function getPlayerState(player: Player): PlayerState
	local state = playerStates[player]
	if not state then
		state = {
			lastFireTime = -math.huge,
			missiles = {},
			steering = false,
			aimOrigin = nil,
			aimDirection = nil,
			lastAimTime = -math.huge,
		}
		playerStates[player] = state
	end
	return state
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	for _, component in { value.X, value.Y, value.Z } do
		if component ~= component or math.abs(component) > 1e6 then
			return false
		end
	end
	return true
end

local function sanitizeDirection(value: any): Vector3?
	if not isFiniteVector(value) or value.Magnitude < 1e-3 then
		return nil
	end
	return value.Unit
end

local function getArmedCharacter(player: Player): (Model?, BasePart?, Tool?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local tool = character:FindFirstChild(Config.LauncherToolName)
	if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return nil, nil, nil
	end
	if not tool or not tool:IsA("Tool") then
		return nil, nil, nil
	end
	return character, head, tool
end

local function validAimRay(head: BasePart, origin: any, direction: any): (Vector3?, Vector3?)
	local unit = sanitizeDirection(direction)
	if not unit or not isFiniteVector(origin) then
		return nil, nil
	end
	if (origin - head.Position).Magnitude > Config.MaxAimOriginDistance then
		return nil, nil
	end
	return origin, unit
end

local function getMuzzlePosition(tool: Tool, head: BasePart, aimDirection: Vector3): Vector3
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return head.Position + aimDirection * Config.LaunchForwardOffset
end

local function onFire(player: Player, mode: any, origin: any, direction: any, target: any)
	if mode ~= "Cursor" and mode ~= "Homing" then
		return
	end
	local character, head, tool = getArmedCharacter(player)
	if not character or not head or not tool then
		return
	end
	local aimOrigin, aimDirection = validAimRay(head, origin, direction)
	if not aimOrigin or not aimDirection then
		return
	end

	local state = getPlayerState(player)
	local now = os.clock()
	if now - state.lastFireTime < Config.FireCooldown then
		return
	end
	if #state.missiles >= Config.MaxActiveMissilesPerPlayer then
		return
	end

	local homingTarget: Instance? = nil
	if mode == "Homing" then
		if typeof(target) ~= "Instance" or not Targets.isTarget(target) then
			return
		end
		local targetPosition = Targets.getPosition(target)
		if not targetPosition or (targetPosition - head.Position).Magnitude > Config.LockRange then
			return
		end
		homingTarget = target
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(aimOrigin, aimDirection * MAX_AIM_DISTANCE, params)
	local aimPoint = if hit then hit.Position else aimOrigin + aimDirection * MAX_AIM_DISTANCE

	local launchPosition = getMuzzlePosition(tool, head, aimDirection)
	if homingTarget then
		aimPoint = Targets.getPosition(homingTarget) :: Vector3
	end
	local launchDirection = aimPoint - launchPosition
	if launchDirection.Magnitude < 1 then
		launchDirection = aimDirection
	end

	nextId += 1
	local missile: Missile = {
		id = nextId,
		owner = player,
		mode = mode,
		sim = MissileSim.new(launchPosition, launchDirection),
		target = homingTarget,
		targetPosition = if homingTarget then Targets.getPosition(homingTarget) else nil,
		targetVelocity = Vector3.zero,
		targetVisible = true,
		seekerTimer = 0,
	}
	missiles[missile.id] = missile
	table.insert(state.missiles, missile)
	state.lastFireTime = now
	if mode == "Cursor" then
		state.aimOrigin, state.aimDirection, state.lastAimTime = aimOrigin, aimDirection, now
	end

	remotes.Spawned:FireAllClients(
		missile.id,
		player.UserId,
		mode,
		launchPosition,
		missile.sim.velocity,
		homingTarget,
		workspace:GetServerTimeNow()
	)
end

local function onSetSteering(player: Player, steering: any)
	if typeof(steering) ~= "boolean" then
		return
	end
	local state = getPlayerState(player)
	state.steering = steering
	if steering then
		state.lastAimTime = os.clock()
	end
end

local function onAim(player: Player, origin: any, direction: any)
	local _, head = getArmedCharacter(player)
	if not head then
		local character = player.Character
		local fallback = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not fallback or not fallback:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			return
		end
		head = fallback
	end
	local aimOrigin, aimDirection = validAimRay(head :: BasePart, origin, direction)
	if not aimOrigin then
		return
	end
	local state = getPlayerState(player)
	state.aimOrigin, state.aimDirection, state.lastAimTime = aimOrigin, aimDirection, os.clock()
end

local function removeMissile(missile: Missile)
	missiles[missile.id] = nil
	local state = playerStates[missile.owner]
	if state then
		local index = table.find(state.missiles, missile)
		if index then
			table.remove(state.missiles, index)
		end
	end
end

local function detonate(missile: Missile, position: Vector3, reason: string)
	removeMissile(missile)
	Warhead.detonate(position, missile.owner)
	remotes.Detonated:FireAllClients(missile.id, position, reason)
end

local function getSteeredMissile(state: PlayerState): Missile?
	if not state.steering or os.clock() - state.lastAimTime > Config.AimTimeout then
		return nil
	end
	for i = #state.missiles, 1, -1 do
		local missile = state.missiles[i]
		if missile.mode == "Cursor" then
			return missile
		end
	end
	return nil
end

local function makeRaycastParams(missile: Missile): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = missile.owner.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	return params
end

local function sampleTarget(missile: Missile, frameDt: number, params: RaycastParams)
	local target = missile.target
	if not target or not Targets.isTarget(target) then
		missile.target = nil
		return
	end
	local position = Targets.getPosition(target)
	if not position then
		missile.target = nil
		return
	end

	local physicsVelocity = Targets.getPhysicsVelocity(target)
	if physicsVelocity then
		missile.targetVelocity = physicsVelocity
	elseif missile.targetPosition and frameDt > 0 then
		local measured = (position - missile.targetPosition) / frameDt
		missile.targetVelocity = missile.targetVelocity:Lerp(measured, 0.5)
	end
	missile.targetPosition = position

	missile.seekerTimer -= frameDt
	if missile.seekerTimer <= 0 then
		missile.seekerTimer = 1 / Config.SeekerUpdateRate
		local from = missile.sim.position
		local hit = workspace:Raycast(from, position - from, params)
		missile.targetVisible = hit == nil or Targets.fromPart(hit.Instance) == target
	end
end

local function stepMissile(missile: Missile, steps: number, frameDt: number)
	local params = makeRaycastParams(missile)
	local state = playerStates[missile.owner]
	local steered = state and getSteeredMissile(state) == missile

	if missile.mode == "Homing" then
		sampleTarget(missile, frameDt, params)
	end

	for i = 1, steps do
		local sim = missile.sim
		local guide: MissileSim.Guide? = nil
		local targetFrom, targetTo

		if missile.mode == "Homing" and missile.target and missile.targetPosition then
			local lead = (i - steps) * STEP
			targetTo = missile.targetPosition + missile.targetVelocity * lead
			targetFrom = targetTo - missile.targetVelocity * STEP
			guide = {
				kind = "Target",
				position = targetTo,
				velocity = missile.targetVelocity,
				visible = missile.targetVisible,
			}
		elseif steered and state and state.aimOrigin and state.aimDirection then
			guide = { kind = "Ray", origin = state.aimOrigin, direction = state.aimDirection }
		end

		local from = sim.position
		MissileSim.step(sim, STEP, guide)
		local to = sim.position

		local hit = workspace:Spherecast(from, Config.CollisionRadius, to - from, params)
		if hit then
			detonate(missile, hit.Position, "Impact")
			return
		end
		if targetFrom and targetTo then
			local fuzePoint = MissileSim.fuze(from, to, targetFrom, targetTo, sim.age)
			if fuzePoint then
				detonate(missile, fuzePoint, "Proximity")
				return
			end
		end
		if not sim.alive then
			detonate(missile, to, sim.deathReason or "Expired")
			return
		end
	end
end

local function onHeartbeat(frameDt: number)
	accumulator = math.min(accumulator + frameDt, STEP * MAX_STEPS_PER_FRAME)
	local steps = math.floor(accumulator / STEP)
	accumulator -= steps * STEP

	if steps > 0 then
		for _, missile in missiles do
			stepMissile(missile, steps, frameDt)
		end
	end

	snapshotTimer -= frameDt
	if snapshotTimer <= 0 then
		snapshotTimer = 1 / Config.SnapshotRate
		local serverTime = workspace:GetServerTimeNow()
		for id, missile in missiles do
			remotes.Snapshot:FireAllClients(
				id,
				missile.sim.position,
				missile.sim.velocity,
				missile.sim.guided,
				serverTime
			)
		end
	end
end

function MissileService.start()
	remotes.Fire.OnServerEvent:Connect(onFire)
	remotes.SetSteering.OnServerEvent:Connect(onSetSteering)
	remotes.Aim.OnServerEvent:Connect(onAim)
	Players.PlayerRemoving:Connect(function(player)
		local state = playerStates[player]
		if state then
			state.steering = false
		end
		playerStates[player] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MissileService
