--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("HomingMissile").Config)
local Demo = Config.Demo

local DroneTargets = {}

type Drone = {
	model: Model,
	radius: number,
	altitude: number,
	angularSpeed: number,
	phase: number,
	time: number,
	jinkTimer: number,
	jinkOffset: Vector3,
	jinkTarget: Vector3,
	alive: boolean,
}

local container: Folder
local random = Random.new()

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildModel(index: number): Model
	local model = Instance.new("Model")
	model.Name = `Drone{index}`

	local body = makePart("Body", Vector3.new(4, 1.4, 4), Color3.fromRGB(45, 45, 52), Enum.Material.Metal)
	body.Parent = model
	model.PrimaryPart = body

	local hitbox = makePart("Hitbox", body.Size * 3, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	hitbox.CanQuery = true
	hitbox.CanTouch = false
	hitbox.CFrame = body.CFrame
	hitbox.Parent = model

	local eye = makePart("Eye", Vector3.new(1, 0.6, 0.4), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	eye.CFrame = body.CFrame * CFrame.new(0, 0, -2.1)
	eye.Parent = model

	for i, offset in
		{
			Vector3.new(2.6, 0.5, 2.6),
			Vector3.new(-2.6, 0.5, 2.6),
			Vector3.new(2.6, 0.5, -2.6),
			Vector3.new(-2.6, 0.5, -2.6),
		}
	do
		local arm = makePart(`Arm{i}`, Vector3.new(0.3, 0.3, 3.2), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		arm.CFrame = CFrame.lookAt(body.Position + offset * 0.5, body.Position + offset)
		arm.Parent = model

		local rotor = makePart(
			`Rotor{i}`,
			Vector3.new(0.15, 2.4, 2.4),
			Color3.fromRGB(200, 200, 210),
			Enum.Material.SmoothPlastic
		)
		rotor.Shape = Enum.PartType.Cylinder
		rotor.Transparency = 0.4
		rotor.CFrame = CFrame.new(body.Position + offset) * CFrame.Angles(0, 0, math.rad(90))
		rotor.Parent = model
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 60)
	light.Range = 10
	light.Brightness = 2
	light.Parent = eye

	model:SetAttribute("Health", Demo.DroneHealth)
	CollectionService:AddTag(model, Config.TargetTag)
	return model
end

local function positionAt(drone: Drone, t: number): Vector3
	local angle = drone.phase + drone.angularSpeed * t
	return Vector3.new(
		math.cos(angle) * drone.radius,
		drone.altitude + math.sin(angle * 2) * 15,
		math.sin(angle) * drone.radius
	) + drone.jinkOffset
end

local function explode(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 8
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
end

local function spawnDrone(index: number): Drone
	local drone: Drone = {
		model = buildModel(index),
		radius = random:NextNumber(Demo.ArenaRadius * 0.4, Demo.ArenaRadius),
		altitude = random:NextNumber(Demo.MinAltitude, Demo.MaxAltitude),
		angularSpeed = 0,
		phase = random:NextNumber(0, math.pi * 2),
		time = 0,
		jinkTimer = random:NextNumber(2, 5),
		jinkOffset = Vector3.zero,
		jinkTarget = Vector3.zero,
		alive = true,
	}
	drone.angularSpeed = Demo.DroneSpeed / drone.radius * (if index % 2 == 0 then 1 else -1)
	drone.model:PivotTo(CFrame.new(positionAt(drone, 0)))
	drone.model.Parent = container
	return drone
end

function DroneTargets.start()
	container = Instance.new("Folder")
	container.Name = "Drones"
	container.Parent = workspace

	local drones: { Drone } = {}
	for i = 1, Demo.DroneCount do
		drones[i] = spawnDrone(i)
	end

	RunService.Heartbeat:Connect(function(dt)
		for index, drone in drones do
			if not drone.alive then
				continue
			end

			local health = drone.model:GetAttribute("Health")
			if typeof(health) == "number" and health <= 0 then
				drone.alive = false
				explode(drone.model:GetPivot().Position)
				drone.model:Destroy()
				task.delay(Demo.DroneRespawnTime, function()
					drones[index] = spawnDrone(index)
				end)
				continue
			end

			drone.jinkTimer -= dt
			if drone.jinkTimer <= 0 then
				drone.jinkTimer = random:NextNumber(2, 5)
				drone.jinkTarget = random:NextUnitVector() * random:NextNumber(10, 30)
			end
			drone.jinkOffset = drone.jinkOffset:Lerp(drone.jinkTarget, math.min(dt * 1.5, 1))

			drone.time += dt
			local position = positionAt(drone, drone.time)
			local ahead = positionAt(drone, drone.time + 0.1)
			drone.model:PivotTo(CFrame.lookAt(position, ahead))
		end
	end)
end

return DroneTargets
