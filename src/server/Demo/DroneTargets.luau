--!strict

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
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
	velocity: Vector3,
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
	model:SetAttribute("DestroyOnHit", true)
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

local function closestPointOnPart(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return part.CFrame:PointToWorldSpace(clamped)
end

local function wreck(drone: Drone, blastPosition: Vector3)
	local model = drone.model
	CollectionService:RemoveTag(model, Config.TargetTag)
	local hitbox = model:FindFirstChild("Hitbox")
	if hitbox then
		hitbox:Destroy()
	end

	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	local impact = blastPosition
	local nearest = math.huge
	for _, part in parts do
		local point = closestPointOnPart(part, blastPosition)
		local distance = (point - blastPosition).Magnitude
		if distance < nearest then
			impact, nearest = point, distance
		end
	end

	local survivors: { BasePart } = {}
	for _, part in parts do
		if (closestPointOnPart(part, impact) - impact).Magnitude <= Demo.WreckRemoveRadius then
			part:Destroy()
		else
			table.insert(survivors, part)
		end
	end
	if #survivors == 0 then
		model:Destroy()
		return
	end

	local body = model.PrimaryPart
	local core = if body and body.Parent then body else nil
	for _, part in survivors do
		part.Color = Color3.new(0, 0, 0)
		part.Material = Enum.Material.SmoothPlastic
		for _, child in part:GetChildren() do
			if child:IsA("Light") then
				child:Destroy()
			end
		end
		if core and part ~= core then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = core
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(45, 45, 45)
	smoke.Opacity = 0.12
	smoke.Size = 1.5
	smoke.RiseVelocity = 3
	smoke.Parent = core or survivors[1]

	for _, part in survivors do
		part.Anchored = false
		part.CanCollide = true
	end
	for _, part in survivors do
		if part.AssemblyRootPart == part then
			local away = part.Position - blastPosition
			local push = if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis
			part.AssemblyLinearVelocity = drone.velocity + push * Demo.WreckBlastSpeed
			part.AssemblyAngularVelocity = random:NextUnitVector() * random:NextNumber(2, 6)
		end
	end

	model.Name ..= "Wreck"
	Debris:AddItem(model, Demo.WreckLifetime)
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
		velocity = Vector3.zero,
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
				local pivot = drone.model:GetPivot().Position
				local hitPosition = drone.model:GetAttribute("LastHitPosition")
				explode(pivot)
				wreck(drone, if typeof(hitPosition) == "Vector3" then hitPosition else pivot)
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
			if dt > 0 then
				drone.velocity = (position - drone.model:GetPivot().Position) / dt
			end
			drone.model:PivotTo(CFrame.lookAt(position, ahead))
		end
	end)
end

return DroneTargets
