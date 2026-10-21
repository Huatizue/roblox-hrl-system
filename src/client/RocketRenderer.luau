--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)
local MissileSim = require(Shared.MissileSim)
local Net = require(Shared.Net)
local Targets = require(Shared.Targets)

local RocketVisuals = require(script.Parent.RocketVisuals)

export type SteeringSource = {
	isSteering: () -> boolean,
	getAimRay: () -> Ray,
}

type Rocket = {
	id: number,
	mine: boolean,
	mode: string,
	sim: MissileSim.State,
	visual: RocketVisuals.Visual,
	renderOffset: Vector3,
	target: Instance?,
	targetPosition: Vector3?,
	targetVelocity: Vector3,
	finished: boolean,
	spawnedAt: number,
}

local STEP = 1 / Config.SimulationRate
local MAX_EXTRAPOLATION = 0.5

local RocketRenderer = {}

local localPlayer = Players.LocalPlayer
local rockets: { [number]: Rocket } = {}
local myCursorRockets: { Rocket } = {}
local accumulator = 0
local steering: SteeringSource

local function latencyOf(serverTime: number): number
	return math.clamp(workspace:GetServerTimeNow() - serverTime, 0, MAX_EXTRAPOLATION)
end

local function renderCFrame(rocket: Rocket): CFrame
	local position = rocket.sim.position + rocket.renderOffset
	local velocity = rocket.sim.velocity
	if velocity.Magnitude < 1e-3 then
		return rocket.visual.root.CFrame
	end
	return CFrame.lookAt(position, position + velocity)
end

local function steeredRocket(): Rocket?
	if not steering.isSteering() then
		return nil
	end
	return myCursorRockets[#myCursorRockets]
end

local function guideFor(rocket: Rocket, steered: Rocket?): MissileSim.Guide?
	if rocket.mode == "Homing" and rocket.target and rocket.targetPosition then
		return {
			kind = "Target",
			position = rocket.targetPosition,
			velocity = rocket.targetVelocity,
			visible = true,
		}
	end
	if rocket == steered then
		local ray = steering.getAimRay()
		return { kind = "Ray", origin = ray.Origin, direction = ray.Direction.Unit }
	end
	return nil
end

local function sampleTarget(rocket: Rocket, frameDt: number)
	local target = rocket.target
	if not target or not target.Parent then
		rocket.target = nil
		return
	end
	local position = Targets.getPosition(target)
	if not position then
		return
	end
	if rocket.targetPosition and frameDt > 0 then
		local measured = (position - rocket.targetPosition) / frameDt
		rocket.targetVelocity = rocket.targetVelocity:Lerp(measured, 0.5)
	end
	rocket.targetPosition = position
end

local function advance(rocket: Rocket, dt: number, steered: Rocket?)
	if rocket.sim.alive then
		MissileSim.step(rocket.sim, dt, guideFor(rocket, steered))
	end
end

local function removeFromMine(rocket: Rocket)
	local index = table.find(myCursorRockets, rocket)
	if index then
		table.remove(myCursorRockets, index)
	end
end

local function finish(rocket: Rocket)
	if rocket.finished then
		return
	end
	rocket.finished = true
	rockets[rocket.id] = nil
	removeFromMine(rocket)
	RocketVisuals.destroy(rocket.visual)
end

local function onSpawned(
	id: number,
	ownerUserId: number,
	mode: string,
	origin: Vector3,
	velocity: Vector3,
	target: Instance?,
	serverTime: number
)
	local sim = MissileSim.new(origin, velocity)
	local visual = RocketVisuals.create(CFrame.lookAt(origin, origin + velocity))
	local rocket: Rocket = {
		id = id,
		mine = ownerUserId == localPlayer.UserId,
		mode = mode,
		sim = sim,
		visual = visual,
		renderOffset = Vector3.zero,
		target = target,
		targetPosition = if target then Targets.getPosition(target) else nil,
		targetVelocity = Vector3.zero,
		finished = false,
		spawnedAt = os.clock(),
	}
	rockets[id] = rocket
	if rocket.mine and mode == "Cursor" then
		table.insert(myCursorRockets, rocket)
	end
	RocketVisuals.backblast(origin, velocity.Unit)

	local steered = steeredRocket()
	local remaining = latencyOf(serverTime)
	while remaining > 0 do
		local dt = math.min(STEP, remaining)
		advance(rocket, dt, steered)
		remaining -= dt
	end
end

local function onSnapshot(id: number, position: Vector3, velocity: Vector3, _guided: boolean, serverTime: number)
	local rocket = rockets[id]
	if not rocket then
		return
	end
	local sim = rocket.sim
	local corrected = position + velocity * latencyOf(serverTime)
	local visualPosition = sim.position + rocket.renderOffset

	sim.position = corrected
	sim.velocity = velocity
	sim.speed = math.max(velocity.Magnitude, 1e-3)

	local offset = visualPosition - corrected
	rocket.renderOffset = if offset.Magnitude > Config.CorrectionSnapDistance then Vector3.zero else offset
end

local function onDetonated(id: number, position: Vector3, _reason: string)
	local rocket = rockets[id]
	if rocket then
		rocket.visual.root.CFrame = CFrame.new(position) * renderCFrame(rocket).Rotation
		finish(rocket)
	end
	RocketVisuals.explode(position)
end

local function onRenderStepped(frameDt: number)
	accumulator = math.min(accumulator + frameDt, STEP * 8)
	local steps = math.floor(accumulator / STEP)
	accumulator -= steps * STEP
	local steered = steeredRocket()
	local decay = math.exp(-frameDt / Config.CorrectionBlendTime)

	for _, rocket in rockets do
		sampleTarget(rocket, frameDt)
		for _ = 1, steps do
			advance(rocket, STEP, steered)
		end
		rocket.renderOffset *= decay
		rocket.visual.root.CFrame = renderCFrame(rocket)
		RocketVisuals.setMotorBurning(rocket.visual, rocket.sim.alive and rocket.sim.age <= Config.BurnTime)

		if os.clock() - rocket.spawnedAt > Config.MaxLifetime + 3 then
			finish(rocket)
		end
	end
end

function RocketRenderer.start(source: SteeringSource)
	steering = source
	local remotes = Net.get()
	remotes.Spawned.OnClientEvent:Connect(onSpawned)
	remotes.Snapshot.OnClientEvent:Connect(onSnapshot)
	remotes.Detonated.OnClientEvent:Connect(onDetonated)
	RunService.RenderStepped:Connect(onRenderStepped)
end

function RocketRenderer.hasSteerableRocket(): boolean
	return #myCursorRockets > 0
end

return RocketRenderer
