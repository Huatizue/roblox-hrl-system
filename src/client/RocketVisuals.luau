--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local RocketVisuals = {}

export type Visual = {
	model: Model,
	root: BasePart,
	exhaust: Attachment,
	emitters: { ParticleEmitter },
	trail: Trail?,
	light: PointLight?,
}

local effectsFolder: Folder? = nil
local function getEffectsFolder(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "RocketEffects"
	folder.Parent = workspace
	effectsFolder = folder
	return folder
end

local function prepare(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
end

local function buildPlaceholder(): Model
	local model = Instance.new("Model")
	model.Name = "Rocket"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.5, 0.5, 3)
	root.Color = Color3.fromRGB(210, 210, 215)
	root.Material = Enum.Material.Metal
	root.Parent = model
	model.PrimaryPart = root

	local nose = Instance.new("Part")
	nose.Name = "Nose"
	nose.Shape = Enum.PartType.Ball
	nose.Size = Vector3.new(0.5, 0.5, 0.5)
	nose.Color = Color3.fromRGB(200, 40, 40)
	nose.Material = Enum.Material.SmoothPlastic
	nose.CFrame = root.CFrame * CFrame.new(0, 0, -1.5)
	nose.Parent = model

	for i = 0, 3 do
		local fin = Instance.new("Part")
		fin.Name = `Fin{i}`
		fin.Size = Vector3.new(0.08, 0.6, 0.6)
		fin.Color = Color3.fromRGB(60, 60, 66)
		fin.Material = Enum.Material.Metal
		fin.CFrame = root.CFrame * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 0.45, 1.2)
		fin.Parent = model
	end

	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(0, 0, 1.55)
	exhaust.Parent = root

	return model
end

local function loadModel(): Model
	local assets = Shared:FindFirstChild("Assets")
	local custom = assets and assets:FindFirstChild("Rocket")
	if custom and custom:IsA("Model") then
		local model = custom:Clone()
		local root = model:FindFirstChild("Root")
		if not model.PrimaryPart and root and root:IsA("BasePart") then
			model.PrimaryPart = root
		end
		return model
	end
	return buildPlaceholder()
end

local function rig(model: Model): BasePart
	local pivot = model:GetPivot()
	local root = Instance.new("Part")
	root.Name = "RocketRoot"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CFrame = pivot
	root.Anchored = true
	prepare(root)
	root.Parent = model

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			prepare(descendant)
			descendant.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = root
		end
	end
	model.PrimaryPart = root
	return root
end

local function makeFlame(parent: Attachment): ParticleEmitter
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = FIRE_TEXTURE
	flame.EmissionDirection = Enum.NormalId.Back
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 200)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 150, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 40, 10)),
	})
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.LightEmission = 1
	flame.LightInfluence = 0
	flame.Lifetime = NumberRange.new(0.06, 0.14)
	flame.Rate = 240
	flame.Speed = NumberRange.new(18, 28)
	flame.SpreadAngle = Vector2.new(8, 8)
	flame.Rotation = NumberRange.new(0, 360)
	flame.LockedToPart = true
	flame.Parent = parent
	return flame
end

local function makeSmoke(parent: Attachment): ParticleEmitter
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = SMOKE_TEXTURE
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235), Color3.fromRGB(150, 150, 150))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.LightInfluence = 1
	smoke.Lifetime = NumberRange.new(1.8, 2.8)
	smoke.Rate = 140
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Drag = 2
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Acceleration = Vector3.new(0, 1.5, 0)
	smoke.Parent = parent
	return smoke
end

function RocketVisuals.create(cframe: CFrame): Visual
	local model = loadModel()
	model:PivotTo(cframe)
	local root = rig(model)

	local exhaust = model:FindFirstChild("Exhaust", true)
	if not exhaust or not exhaust:IsA("Attachment") then
		local _, size = model:GetBoundingBox()
		local created = Instance.new("Attachment")
		created.Name = "Exhaust"
		created.Position = Vector3.new(0, 0, size.Z / 2)
		created.Parent = root
		exhaust = created
	end
	local exhaustAttachment = exhaust :: Attachment

	local emitters = { makeFlame(exhaustAttachment), makeSmoke(exhaustAttachment) }

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 60)
	light.Range = 16
	light.Brightness = 3
	light.Parent = exhaustAttachment

	local trailTop = Instance.new("Attachment")
	trailTop.Position = exhaustAttachment.Position + Vector3.new(0, 0.15, 0)
	trailTop.Parent = exhaustAttachment.Parent
	local trailBottom = Instance.new("Attachment")
	trailBottom.Position = exhaustAttachment.Position - Vector3.new(0, 0.15, 0)
	trailBottom.Parent = exhaustAttachment.Parent
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 90, 30))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.FaceCamera = true
	trail.Parent = root

	model.Parent = getEffectsFolder()
	return {
		model = model,
		root = root,
		exhaust = exhaustAttachment,
		emitters = emitters,
		trail = trail,
		light = light,
	}
end

function RocketVisuals.setMotorBurning(visual: Visual, burning: boolean)
	for _, emitter in visual.emitters do
		if emitter.Name == "Flame" then
			emitter.Enabled = burning
		end
	end
	if visual.light then
		visual.light.Enabled = burning
	end
end

function RocketVisuals.destroy(visual: Visual)
	for _, part in visual.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	for _, emitter in visual.emitters do
		emitter.Enabled = false
	end
	if visual.light then
		visual.light.Enabled = false
	end
	if visual.trail then
		visual.trail.Enabled = false
	end
	Debris:AddItem(visual.model, 3)
end

function RocketVisuals.backblast(position: Vector3, direction: Vector3)
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.lookAt(position, position + direction)
	prepare(anchor)
	anchor.Parent = getEffectsFolder()

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local smoke = makeSmoke(attachment)
	smoke.Enabled = false
	smoke.Speed = NumberRange.new(6, 14)
	smoke.SpreadAngle = Vector2.new(35, 35)
	smoke:Emit(30)
	local flash = makeFlame(attachment)
	flash.Enabled = false
	flash:Emit(25)

	Debris:AddItem(anchor, 4)
end

function RocketVisuals.explode(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 10
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	local fireball = Instance.new("Part")
	fireball.Shape = Enum.PartType.Ball
	fireball.Material = Enum.Material.Neon
	fireball.Color = Color3.fromRGB(255, 150, 50)
	fireball.Size = Vector3.new(2, 2, 2)
	fireball.Anchored = true
	fireball.CFrame = CFrame.new(position)
	prepare(fireball)
	fireball.Parent = getEffectsFolder()

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 60)
	light.Range = 40
	light.Brightness = 6
	light.Parent = fireball

	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(fireball, info, { Size = Vector3.new(16, 16, 16), Transparency = 1 }):Play()
	TweenService:Create(light, info, { Brightness = 0 }):Play()

	local attachment = Instance.new("Attachment")
	attachment.Parent = fireball
	local smoke = makeSmoke(attachment)
	smoke.Enabled = false
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Speed = NumberRange.new(4, 10)
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90), Color3.fromRGB(50, 50, 50))
	smoke:Emit(40)

	Debris:AddItem(fireball, 4)
end

return RocketVisuals
